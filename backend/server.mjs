import http from "node:http";
import { pathToFileURL } from "node:url";
import {
  createLensPilotCreativeInterpretationApi,
  lensPilotCreativeInterpretationApiDefaults,
  lensPilotCreativeInterpretationApiPrivacy,
} from "./api/creative-interpretation.mjs";

export const lensPilotCreativeServerDefaults = {
  host: "127.0.0.1",
  port: 8787,
  healthPath: "/health",
  readyPath: "/ready",
  creativePath: lensPilotCreativeInterpretationApiDefaults.path,
  maxRequestBytes: 64 * 1024,
  rateLimitWindowMs: 60_000,
  rateLimitMaxRequests: 30,
};

export function createLensPilotCreativeHTTPServer(options = {}) {
  const environment = options.environment ?? globalThis.process?.env ?? {};
  const config = makeServerConfig(options, environment);
  const creativeApi = createLensPilotCreativeInterpretationApi({
    ...options,
    environment,
  });
  const rateLimiter = createMemoryRateLimiter({
    windowMs: config.rateLimitWindowMs,
    maxRequests: config.rateLimitMaxRequests,
    now: options.nowMs ?? Date.now,
  });

  return http.createServer(async (request, response) => {
    const result = await handleLensPilotCreativeHTTPRoute(request, {
      config,
      creativeApi,
      rateLimiter,
    });
    writeNodeResponse(response, result);
  });
}

export async function handleLensPilotCreativeHTTPRoute(requestLike, options = {}) {
  const environment = options.environment ?? globalThis.process?.env ?? {};
  const config = options.config ?? makeServerConfig(options, environment);
  const creativeApi = options.creativeApi ?? createLensPilotCreativeInterpretationApi({
    ...options,
    environment,
  });
  const rateLimiter = options.rateLimiter ?? createMemoryRateLimiter({
    windowMs: config.rateLimitWindowMs,
    maxRequests: config.rateLimitMaxRequests,
    now: options.nowMs ?? Date.now,
  });

  const method = String(requestLike?.method ?? "GET").toUpperCase();
  const url = requestURL(requestLike, config);
  const path = url.pathname.replace(/\/+$/, "") || "/";
  const headers = normalizeIncomingHeaders(requestLike?.headers);
  const origin = headerValue(headers, "origin");
  const corsHeaders = corsResponseHeaders(origin, config.allowedOrigins);

  if (method === "OPTIONS") {
    return jsonResponse(204, "", {
      ...corsHeaders,
      "access-control-allow-methods": "GET,POST,OPTIONS",
      "access-control-allow-headers": "authorization,content-type,x-lenspilot-client",
      "access-control-max-age": "600",
    });
  }

  if (path === config.healthPath) {
    return jsonResponse(200, {
      status: "ok",
      service: "lenspilot-creative-api",
      apiVersion: lensPilotCreativeInterpretationApiDefaults.apiVersion,
      creativePath: config.creativePath,
      privacy: lensPilotCreativeInterpretationApiPrivacy,
    }, corsHeaders);
  }

  if (path === config.readyPath) {
    const configured = Boolean(config.openAIAPIKeyConfigured);
    return jsonResponse(configured ? 200 : 503, {
      status: configured ? "ready" : "not_ready",
      service: "lenspilot-creative-api",
      apiVersion: lensPilotCreativeInterpretationApiDefaults.apiVersion,
      openAIConfigured: configured,
      clientAuthorizationConfigured: Boolean(config.clientAuthorizationConfigured),
      rateLimit: {
        windowMs: config.rateLimitWindowMs,
        maxRequests: config.rateLimitMaxRequests,
      },
    }, corsHeaders);
  }

  if (path !== config.creativePath) {
    return jsonResponse(404, {
      error: {
        code: "not_found",
        message: "LensPilot API route not found.",
      },
    }, corsHeaders);
  }

  const clientKey = clientRateLimitKey(requestLike, headers);
  const rateLimit = rateLimiter.take(clientKey);
  if (!rateLimit.allowed) {
    return jsonResponse(429, {
      error: {
        code: "rate_limited",
        message: "Too many creative guidance requests.",
      },
    }, {
      ...corsHeaders,
      "retry-after": String(Math.max(1, Math.ceil(rateLimit.retryAfterMs / 1000))),
      "x-ratelimit-limit": String(config.rateLimitMaxRequests),
      "x-ratelimit-remaining": "0",
      "x-ratelimit-reset": String(rateLimit.resetAt),
    });
  }

  let body;
  try {
    body = await collectRequestBody(requestLike, config.maxRequestBytes);
  } catch {
    return jsonResponse(413, {
      error: {
        code: "request_body_too_large",
        message: "Creative API request body is too large.",
      },
    }, corsHeaders);
  }

  const creativeResult = await creativeApi.handle({
    method,
    headers,
    body,
  });

  return {
    ...creativeResult,
    headers: {
      ...creativeResult.headers,
      ...corsHeaders,
      "x-ratelimit-limit": String(config.rateLimitMaxRequests),
      "x-ratelimit-remaining": String(rateLimit.remaining),
      "x-ratelimit-reset": String(rateLimit.resetAt),
    },
  };
}

function makeServerConfig(options, environment) {
  const host = cleanOptional(options.host ?? environment.LENSPILOT_API_HOST) ??
    lensPilotCreativeServerDefaults.host;
  const port = parseIntegerOption(
    options.port ?? environment.PORT ?? environment.LENSPILOT_API_PORT,
    lensPilotCreativeServerDefaults.port
  );

  return {
    host,
    port,
    healthPath: cleanPath(options.healthPath) ?? lensPilotCreativeServerDefaults.healthPath,
    readyPath: cleanPath(options.readyPath) ?? lensPilotCreativeServerDefaults.readyPath,
    creativePath: cleanPath(options.creativePath) ?? lensPilotCreativeServerDefaults.creativePath,
    maxRequestBytes: parseIntegerOption(
      options.maxRequestBytes ?? environment.LENSPILOT_MAX_REQUEST_BYTES,
      lensPilotCreativeServerDefaults.maxRequestBytes
    ),
    rateLimitWindowMs: parseIntegerOption(
      options.rateLimitWindowMs ?? environment.LENSPILOT_RATE_LIMIT_WINDOW_MS,
      lensPilotCreativeServerDefaults.rateLimitWindowMs
    ),
    rateLimitMaxRequests: parseIntegerOption(
      options.rateLimitMaxRequests ?? environment.LENSPILOT_RATE_LIMIT_MAX,
      lensPilotCreativeServerDefaults.rateLimitMaxRequests
    ),
    allowedOrigins: parseAllowedOrigins(options.allowedOrigins ?? environment.LENSPILOT_ALLOWED_ORIGINS),
    openAIAPIKeyConfigured: Boolean(cleanOptional(options.openAIAPIKey ?? environment.OPENAI_API_KEY)),
    clientAuthorizationConfigured: Boolean(cleanOptional(options.expectedClientToken ?? environment.LENSPILOT_CREATIVE_API_TOKEN)),
  };
}

function createMemoryRateLimiter({ windowMs, maxRequests, now }) {
  const buckets = new Map();
  const safeWindowMs = Math.max(1_000, windowMs);
  const safeMaxRequests = Math.max(1, maxRequests);

  return {
    take(key) {
      const checkedAt = now();
      const current = buckets.get(key);
      if (!current || current.resetAt <= checkedAt) {
        const resetAt = checkedAt + safeWindowMs;
        buckets.set(key, {
          count: 1,
          resetAt,
        });
        return {
          allowed: true,
          remaining: safeMaxRequests - 1,
          resetAt,
          retryAfterMs: 0,
        };
      }

      if (current.count >= safeMaxRequests) {
        return {
          allowed: false,
          remaining: 0,
          resetAt: current.resetAt,
          retryAfterMs: current.resetAt - checkedAt,
        };
      }

      current.count += 1;
      return {
        allowed: true,
        remaining: safeMaxRequests - current.count,
        resetAt: current.resetAt,
        retryAfterMs: 0,
      };
    },
  };
}

function requestURL(requestLike, config) {
  return new URL(requestLike?.url ?? "/", `http://${config.host}:${config.port}`);
}

async function collectRequestBody(requestLike, maxBytes) {
  if (typeof requestLike?.body === "string") {
    if (Buffer.byteLength(requestLike.body) > maxBytes) throw new Error("request_body_too_large");
    return requestLike.body;
  }
  if (requestLike?.body instanceof Uint8Array) {
    if (requestLike.body.byteLength > maxBytes) throw new Error("request_body_too_large");
    return new TextDecoder().decode(requestLike.body);
  }
  if (isRecord(requestLike?.body)) {
    const body = JSON.stringify(requestLike.body);
    if (Buffer.byteLength(body) > maxBytes) throw new Error("request_body_too_large");
    return body;
  }
  if (typeof requestLike?.json === "function") {
    const body = JSON.stringify(await requestLike.json());
    if (Buffer.byteLength(body) > maxBytes) throw new Error("request_body_too_large");
    return body;
  }
  if (typeof requestLike?.[Symbol.asyncIterator] === "function") {
    const chunks = [];
    let byteCount = 0;
    for await (const chunk of requestLike) {
      const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
      byteCount += buffer.byteLength;
      if (byteCount > maxBytes) throw new Error("request_body_too_large");
      chunks.push(buffer);
    }
    return Buffer.concat(chunks).toString("utf8");
  }
  return "";
}

function writeNodeResponse(response, result) {
  response.writeHead(result.status, result.headers);
  response.end(result.body);
}

function jsonResponse(status, payload, headers = {}) {
  const body = typeof payload === "string" ? payload : JSON.stringify(payload);
  return {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      ...headers,
    },
    body,
  };
}

function corsResponseHeaders(origin, allowedOrigins) {
  if (!origin || allowedOrigins.length === 0) return {};
  if (allowedOrigins.includes("*") || allowedOrigins.includes(origin)) {
    return {
      "access-control-allow-origin": origin,
      "vary": "Origin",
    };
  }
  return {};
}

function clientRateLimitKey(requestLike, headers) {
  const forwarded = headerValue(headers, "x-forwarded-for");
  if (forwarded) return forwarded.split(",")[0].trim();
  return requestLike?.socket?.remoteAddress ?? "unknown";
}

function normalizeIncomingHeaders(headers) {
  if (!headers) return {};
  if (typeof headers.get === "function") {
    const normalized = {};
    headers.forEach((value, key) => {
      normalized[key.toLowerCase()] = String(value);
    });
    return normalized;
  }
  if (Array.isArray(headers)) {
    return Object.fromEntries(headers.map(([key, value]) => [String(key).toLowerCase(), String(value)]));
  }
  if (isRecord(headers)) {
    return Object.fromEntries(
      Object.entries(headers).map(([key, value]) => [key.toLowerCase(), String(value)])
    );
  }
  return {};
}

function headerValue(headers, name) {
  return headers[name.toLowerCase()];
}

function parseAllowedOrigins(value) {
  if (Array.isArray(value)) return value.map(String).map((item) => item.trim()).filter(Boolean);
  const cleaned = cleanOptional(value);
  if (!cleaned) return [];
  return cleaned.split(",").map((item) => item.trim()).filter(Boolean);
}

function parseIntegerOption(value, fallback) {
  const parsed = typeof value === "number" ? value : Number.parseInt(String(value ?? ""), 10);
  return Number.isFinite(parsed) && parsed > 0 ? Math.trunc(parsed) : fallback;
}

function cleanPath(value) {
  const cleaned = cleanOptional(value);
  if (!cleaned) return undefined;
  return cleaned.startsWith("/") ? cleaned.replace(/\/+$/, "") || "/" : `/${cleaned}`.replace(/\/+$/, "");
}

function cleanOptional(value) {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function isRecord(value) {
  return typeof value === "object" && value !== null;
}

function isMainModule() {
  return process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
}

if (isMainModule()) {
  const server = createLensPilotCreativeHTTPServer();
  const host = process.env.LENSPILOT_API_HOST ?? lensPilotCreativeServerDefaults.host;
  const port = Number.parseInt(process.env.PORT ?? process.env.LENSPILOT_API_PORT ?? String(lensPilotCreativeServerDefaults.port), 10);
  server.listen(port, host, () => {
    console.log(JSON.stringify({
      service: "lenspilot-creative-api",
      status: "listening",
      host,
      port,
      healthPath: lensPilotCreativeServerDefaults.healthPath,
      readyPath: lensPilotCreativeServerDefaults.readyPath,
      creativePath: lensPilotCreativeServerDefaults.creativePath,
    }));
  });
}
