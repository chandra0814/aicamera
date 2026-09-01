import http from "node:http";
import { createHash, createHmac, timingSafeEqual } from "node:crypto";
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
  metricsPath: "/metrics",
  creativePath: lensPilotCreativeInterpretationApiDefaults.path,
  maxRequestBytes: 64 * 1024,
  rateLimitWindowMs: 60_000,
  rateLimitMaxRequests: 30,
  metricsEnabled: true,
  maxMetricEvents: 100,
  signedRequestsRequired: false,
  signatureToleranceMs: 5 * 60 * 1000,
  signatureReplayMaxEntries: 1000,
  productionMaxRequestBytes: 64 * 1024,
  productionMaxRequestsPerWindow: 120,
  requireProductionSafety: false,
};

export function createLensPilotCreativeHTTPServer(options = {}) {
  const environment = options.environment ?? globalThis.process?.env ?? {};
  const config = makeServerConfig(options, environment);
  const nowMs = options.nowMs ?? Date.now;
  const creativeApi = createLensPilotCreativeInterpretationApi({
    ...options,
    environment,
  });
  const rateLimiter = createMemoryRateLimiter({
    windowMs: config.rateLimitWindowMs,
    maxRequests: config.rateLimitMaxRequests,
    now: nowMs,
  });
  const telemetry = options.telemetry ?? createLensPilotCreativeOperationalTelemetry({
    maxEvents: config.maxMetricEvents,
    nowMs,
  });
  const replayGuard = options.replayGuard ?? createMemoryReplayGuard({
    windowMs: config.signatureToleranceMs,
    maxEntries: config.signatureReplayMaxEntries,
    now: nowMs,
  });

  return http.createServer(async (request, response) => {
    const result = await handleLensPilotCreativeHTTPRoute(request, {
      config,
      creativeApi,
      rateLimiter,
      telemetry,
      replayGuard,
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
  const telemetry = options.telemetry;
  const replayGuard = options.replayGuard ?? createMemoryReplayGuard({
    windowMs: config.signatureToleranceMs,
    maxEntries: config.signatureReplayMaxEntries,
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
      "access-control-allow-headers": "authorization,content-type,x-lenspilot-client,x-lenspilot-request-id,x-lenspilot-timestamp,x-lenspilot-signature",
      "access-control-max-age": "600",
    });
  }

  if (path === config.healthPath) {
    return jsonResponse(200, {
      status: "ok",
      service: "lenspilot-creative-api",
      apiVersion: lensPilotCreativeInterpretationApiDefaults.apiVersion,
      creativePath: config.creativePath,
      metricsPath: config.metricsEnabled ? config.metricsPath : null,
      privacy: lensPilotCreativeInterpretationApiPrivacy,
    }, corsHeaders);
  }

  if (path === config.readyPath) {
    const configured = Boolean(config.openAIAPIKeyConfigured);
    const deployment = describeLensPilotCreativeServerConfig({
      config,
    });
    const ready = configured && (!config.requireProductionSafety || deployment.productionSafety.ready);
    return jsonResponse(ready ? 200 : 503, {
      status: ready ? "ready" : "not_ready",
      service: "lenspilot-creative-api",
      apiVersion: lensPilotCreativeInterpretationApiDefaults.apiVersion,
      openAIConfigured: configured,
      clientAuthorizationConfigured: Boolean(config.clientAuthorizationConfigured),
      clientSignatureConfigured: Boolean(config.clientSignatureConfigured),
      signedRequestsRequired: Boolean(config.signedRequestsRequired),
      rateLimit: {
        windowMs: config.rateLimitWindowMs,
        maxRequests: config.rateLimitMaxRequests,
      },
      signedRequestPolicy: {
        toleranceMs: config.signatureToleranceMs,
        replayMaxEntries: config.signatureReplayMaxEntries,
      },
      requestBody: {
        maxBytes: config.maxRequestBytes,
      },
      telemetry: {
        metricsEnabled: config.metricsEnabled,
        metricsAuthorizationConfigured: Boolean(config.metricsAuthorizationConfigured),
        maxRecentEvents: config.maxMetricEvents,
      },
      cors: {
        allowedOriginsConfigured: config.allowedOrigins.length,
        wildcardAllowed: config.allowedOrigins.includes("*"),
      },
      productionSafety: deployment.productionSafety,
    }, corsHeaders);
  }

  if (path === config.metricsPath) {
    if (!config.metricsEnabled) {
      return jsonResponse(404, {
        error: {
          code: "not_found",
          message: "LensPilot API route not found.",
        },
      }, corsHeaders);
    }
    if (config.requireProductionSafety && !config.metricsAuthorizationConfigured) {
      return jsonResponse(503, {
        error: {
          code: "metrics_authorization_required",
          message: "Creative API metrics require authorization in production mode.",
        },
      }, corsHeaders);
    }
    if (config.expectedMetricsToken) {
      const expectedAuthorization = `Bearer ${config.expectedMetricsToken}`;
      if (headerValue(headers, "authorization") !== expectedAuthorization) {
        return jsonResponse(401, {
          error: {
            code: "unauthorized",
            message: "Creative API metrics authorization failed.",
          },
        }, corsHeaders);
      }
    }

    return jsonResponse(200, makeLensPilotCreativeMetricsResponse(config, telemetry), corsHeaders);
  }

  if (path !== config.creativePath) {
    return jsonResponse(404, {
      error: {
        code: "not_found",
        message: "LensPilot API route not found.",
      },
    }, corsHeaders);
  }

  const telemetryStartedAt = telemetry?.markStart?.();
  const completeCreativeRoute = (result) => {
    recordLensPilotCreativeRouteTelemetry(telemetry, {
      method,
      path,
      startedAt: telemetryStartedAt,
      result,
    });
    return result;
  };

  const clientKey = clientRateLimitKey(requestLike, headers);
  const rateLimit = rateLimiter.take(clientKey);
  if (!rateLimit.allowed) {
    return completeCreativeRoute(jsonResponse(429, {
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
    }));
  }

  let body;
  try {
    body = await collectRequestBody(requestLike, config.maxRequestBytes);
  } catch {
    return completeCreativeRoute(jsonResponse(413, {
      error: {
        code: "request_body_too_large",
        message: "Creative API request body is too large.",
      },
    }, corsHeaders));
  }

  const signedRequest = validateLensPilotSignedPhoneRequest({
    method,
    path,
    headers,
    body,
    config,
    replayGuard,
  });
  if (!signedRequest.allowed) {
    return completeCreativeRoute(jsonResponse(signedRequest.status, {
      error: {
        code: signedRequest.code,
        message: signedRequest.message,
      },
    }, corsHeaders));
  }

  const creativeResult = await creativeApi.handle({
    method,
    headers,
    body,
  });

  return completeCreativeRoute({
    ...creativeResult,
    headers: {
      ...creativeResult.headers,
      ...corsHeaders,
      "x-ratelimit-limit": String(config.rateLimitMaxRequests),
      "x-ratelimit-remaining": String(rateLimit.remaining),
      "x-ratelimit-reset": String(rateLimit.resetAt),
    },
  });
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
    metricsPath: cleanPath(options.metricsPath) ?? lensPilotCreativeServerDefaults.metricsPath,
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
    clientSigningSecret: cleanOptional(options.clientSigningSecret ?? environment.LENSPILOT_CLIENT_SIGNING_SECRET),
    clientSignatureConfigured: Boolean(cleanOptional(options.clientSigningSecret ?? environment.LENSPILOT_CLIENT_SIGNING_SECRET)),
    signedRequestsRequired: parseBooleanOption(
      options.signedRequestsRequired ?? environment.LENSPILOT_REQUIRE_SIGNED_PHONE_REQUESTS,
      lensPilotCreativeServerDefaults.signedRequestsRequired
    ),
    signatureToleranceMs: parseIntegerOption(
      options.signatureToleranceMs ?? environment.LENSPILOT_SIGNATURE_TOLERANCE_MS,
      lensPilotCreativeServerDefaults.signatureToleranceMs
    ),
    signatureReplayMaxEntries: parseIntegerOption(
      options.signatureReplayMaxEntries ?? environment.LENSPILOT_SIGNATURE_REPLAY_MAX_ENTRIES,
      lensPilotCreativeServerDefaults.signatureReplayMaxEntries
    ),
    metricsEnabled: parseBooleanOption(
      options.metricsEnabled ?? environment.LENSPILOT_ENABLE_METRICS,
      lensPilotCreativeServerDefaults.metricsEnabled
    ),
    expectedMetricsToken: cleanOptional(options.expectedMetricsToken ?? environment.LENSPILOT_METRICS_TOKEN),
    metricsAuthorizationConfigured: Boolean(cleanOptional(options.expectedMetricsToken ?? environment.LENSPILOT_METRICS_TOKEN)),
    maxMetricEvents: parseIntegerOption(
      options.maxMetricEvents ?? environment.LENSPILOT_MAX_METRIC_EVENTS,
      lensPilotCreativeServerDefaults.maxMetricEvents
    ),
    requireProductionSafety: parseBooleanOption(
      options.requireProductionSafety ?? environment.LENSPILOT_REQUIRE_PRODUCTION_SAFETY,
      lensPilotCreativeServerDefaults.requireProductionSafety
    ),
  };
}

export function describeLensPilotCreativeServerConfig(options = {}) {
  const environment = options.environment ?? globalThis.process?.env ?? {};
  const config = options.config ?? makeServerConfig(options, environment);

  return {
    service: "lenspilot-creative-api",
    apiVersion: lensPilotCreativeInterpretationApiDefaults.apiVersion,
    paths: {
      health: config.healthPath,
      ready: config.readyPath,
      metrics: config.metricsEnabled ? config.metricsPath : null,
      creative: config.creativePath,
    },
    openAIConfigured: Boolean(config.openAIAPIKeyConfigured),
    clientAuthorizationConfigured: Boolean(config.clientAuthorizationConfigured),
    clientSignatureConfigured: Boolean(config.clientSignatureConfigured),
    signedRequestsRequired: Boolean(config.signedRequestsRequired),
    metricsAuthorizationConfigured: Boolean(config.metricsAuthorizationConfigured),
    rateLimit: {
      windowMs: config.rateLimitWindowMs,
      maxRequests: config.rateLimitMaxRequests,
    },
    signedRequestPolicy: {
      required: Boolean(config.signedRequestsRequired),
      toleranceMs: config.signatureToleranceMs,
      replayMaxEntries: config.signatureReplayMaxEntries,
      storesRawRequestBody: false,
      storesSignatureSecret: false,
      storesRawRequestId: false,
    },
    requestBody: {
      maxBytes: config.maxRequestBytes,
    },
    telemetry: {
      metricsEnabled: config.metricsEnabled,
      maxRecentEvents: config.maxMetricEvents,
      storesRawRequestBody: false,
      storesPromptText: false,
      storesClientIP: false,
      storesAuthorizationHeader: false,
      storesRawPhoto: false,
      storesRawLearningEvents: false,
    },
    cors: {
      allowedOriginsConfigured: config.allowedOrigins.length,
      wildcardAllowed: config.allowedOrigins.includes("*"),
    },
    privacy: lensPilotCreativeInterpretationApiPrivacy,
    productionSafety: makeProductionSafetyReport(config),
  };
}

function makeProductionSafetyReport(config) {
  const checks = [
    makeProductionSafetyCheck({
      id: "server_openai_key",
      passed: config.openAIAPIKeyConfigured,
      required: true,
      message: "Server-side OPENAI_API_KEY is configured.",
    }),
    makeProductionSafetyCheck({
      id: "phone_client_authorization",
      passed: config.clientAuthorizationConfigured,
      required: config.requireProductionSafety,
      message: "Phone bearer authorization is configured with LENSPILOT_CREATIVE_API_TOKEN.",
    }),
    makeProductionSafetyCheck({
      id: "signed_phone_requests",
      passed: config.clientSignatureConfigured && config.signedRequestsRequired,
      required: config.requireProductionSafety,
      message: "Signed phone requests are required and configured with LENSPILOT_CLIENT_SIGNING_SECRET.",
    }),
    makeProductionSafetyCheck({
      id: "cors_origin_policy",
      passed: !config.allowedOrigins.includes("*"),
      required: config.requireProductionSafety,
      message: config.allowedOrigins.length > 0
        ? "CORS is restricted to configured origins."
        : "CORS is closed to browser origins.",
    }),
    makeProductionSafetyCheck({
      id: "request_body_cap",
      passed: config.maxRequestBytes <= lensPilotCreativeServerDefaults.productionMaxRequestBytes,
      required: config.requireProductionSafety,
      message: `Request body cap is ${config.maxRequestBytes} bytes.`,
    }),
    makeProductionSafetyCheck({
      id: "rate_limit_policy",
      passed: config.rateLimitWindowMs > 0 &&
        config.rateLimitMaxRequests > 0 &&
        config.rateLimitMaxRequests <= lensPilotCreativeServerDefaults.productionMaxRequestsPerWindow,
      required: config.requireProductionSafety,
      message: `Local rate limit is ${config.rateLimitMaxRequests} requests per ${config.rateLimitWindowMs} ms.`,
    }),
    makeProductionSafetyCheck({
      id: "metrics_authorization",
      passed: !config.metricsEnabled || config.metricsAuthorizationConfigured,
      required: config.requireProductionSafety && config.metricsEnabled,
      message: config.metricsEnabled
        ? "Metrics route authorization is configured with LENSPILOT_METRICS_TOKEN."
        : "Metrics route is disabled.",
    }),
    makeProductionSafetyCheck({
      id: "single_phone_privacy_boundary",
      passed: lensPilotCreativeInterpretationApiPrivacy.singlePhoneOnly === true &&
        lensPilotCreativeInterpretationApiPrivacy.acceptsClientOpenAIKey === false &&
        lensPilotCreativeInterpretationApiPrivacy.uploadsLiveCameraFrame === false &&
        lensPilotCreativeInterpretationApiPrivacy.sendsPrivatePhoto === false &&
        lensPilotCreativeInterpretationApiPrivacy.sendsIdentityData === false &&
        lensPilotCreativeInterpretationApiPrivacy.sendsPreciseLocation === false &&
        lensPilotCreativeInterpretationApiPrivacy.sendsRawLearningEvents === false,
      required: true,
      message: "Creative API privacy boundary is single-phone and text-summary only.",
    }),
  ];
  const failedRequiredChecks = checks
    .filter((check) => check.required && check.status !== "pass")
    .map((check) => check.id);
  const warnings = checks
    .filter((check) => !check.required && check.status !== "pass")
    .map((check) => check.id);

  return {
    required: config.requireProductionSafety,
    ready: failedRequiredChecks.length === 0,
    failedRequiredChecks,
    warnings,
    checks,
  };
}

function makeProductionSafetyCheck({ id, passed, required, message }) {
  return {
    id,
    status: passed ? "pass" : "fail",
    required: Boolean(required),
    message,
  };
}

export function createLensPilotCreativeOperationalTelemetry(options = {}) {
  const maxEvents = Math.max(0, Math.min(500, Math.trunc(options.maxEvents ?? lensPilotCreativeServerDefaults.maxMetricEvents)));
  const nowMs = options.nowMs ?? Date.now;
  const startedAt = nowMs();
  const counters = {
    totalRequests: 0,
    creativeRequests: 0,
    successfulResponses: 0,
    clientErrors: 0,
    providerErrors: 0,
    serverErrors: 0,
    unauthorizedRequests: 0,
    unsafeRequests: 0,
    rateLimitedRequests: 0,
    oversizedRequests: 0,
    signedRequestFailures: 0,
    staleSignedRequests: 0,
    replayedSignedRequests: 0,
    billingBlockedProviderRequests: 0,
    retryableProviderFailures: 0,
  };
  const statusCounts = {};
  const errorCounts = {};
  const providerStatusCounts = {};
  const recentEvents = [];

  return {
    markStart() {
      return nowMs();
    },
    record(event) {
      const safeEvent = makeSafeTelemetryEvent(event, nowMs());
      counters.totalRequests += 1;
      if (safeEvent.path === lensPilotCreativeServerDefaults.creativePath || safeEvent.route === "creative_interpretation") {
        counters.creativeRequests += 1;
      }
      if (safeEvent.status >= 200 && safeEvent.status < 300) counters.successfulResponses += 1;
      if (safeEvent.status >= 400 && safeEvent.status < 500) counters.clientErrors += 1;
      if (safeEvent.status >= 500) counters.serverErrors += 1;
      incrementCounter(statusCounts, String(safeEvent.status));

      if (safeEvent.errorCode) {
        incrementCounter(errorCounts, safeEvent.errorCode);
        if (safeEvent.errorCode === "unauthorized") counters.unauthorizedRequests += 1;
        if (safeEvent.errorCode === "unsafe_request") counters.unsafeRequests += 1;
        if (safeEvent.errorCode === "rate_limited") counters.rateLimitedRequests += 1;
        if (safeEvent.errorCode === "request_body_too_large") counters.oversizedRequests += 1;
        if (isSignedRequestFailureCode(safeEvent.errorCode)) counters.signedRequestFailures += 1;
        if (safeEvent.errorCode === "stale_signature") counters.staleSignedRequests += 1;
        if (safeEvent.errorCode === "replayed_request") counters.replayedSignedRequests += 1;
        if (safeEvent.errorCode.startsWith("openai_")) counters.providerErrors += 1;
      }
      if (Number.isFinite(safeEvent.providerStatus)) {
        incrementCounter(providerStatusCounts, String(safeEvent.providerStatus));
        counters.providerErrors += safeEvent.errorCode?.startsWith("openai_") ? 0 : 1;
      }
      if (safeEvent.blockedByBilling) counters.billingBlockedProviderRequests += 1;
      if (safeEvent.retryable) counters.retryableProviderFailures += 1;

      if (maxEvents > 0) {
        recentEvents.push(safeEvent);
        while (recentEvents.length > maxEvents) recentEvents.shift();
      }
    },
    snapshot() {
      return {
        uptimeMs: Math.max(0, nowMs() - startedAt),
        totals: { ...counters },
        statusCounts: sortRecordByKey(statusCounts),
        errorCounts: sortRecordByKey(errorCounts),
        providerStatusCounts: sortRecordByKey(providerStatusCounts),
        recentEvents: recentEvents.map((event) => ({ ...event })),
      };
    },
  };
}

function makeLensPilotCreativeMetricsResponse(config, telemetry) {
  const snapshot = typeof telemetry?.snapshot === "function"
    ? telemetry.snapshot()
    : createLensPilotCreativeOperationalTelemetry({ maxEvents: 0 }).snapshot();

  return {
    service: "lenspilot-creative-api",
    apiVersion: lensPilotCreativeInterpretationApiDefaults.apiVersion,
    generatedAt: new Date().toISOString(),
    paths: {
      creative: config.creativePath,
      metrics: config.metricsPath,
    },
    retention: {
      storesRawRequestBody: false,
      storesPromptText: false,
      storesClientIP: false,
      storesAuthorizationHeader: false,
      storesRawPhoto: false,
      storesRawLearningEvents: false,
      storesIdentityData: false,
      storesPreciseLocation: false,
    },
    privacy: lensPilotCreativeInterpretationApiPrivacy,
    ...snapshot,
  };
}

function recordLensPilotCreativeRouteTelemetry(telemetry, event) {
  if (typeof telemetry?.record !== "function") return;

  const status = Number.isFinite(event.result?.status) ? event.result.status : 0;
  const parsedBody = parseJSONResultBody(event.result?.body);
  const error = isRecord(parsedBody?.error) ? parsedBody.error : {};
  const durationMs = Number.isFinite(event.startedAt)
    ? Math.max(0, telemetry.markStart() - event.startedAt)
    : undefined;

  telemetry.record({
    method: event.method,
    path: event.path,
    route: "creative_interpretation",
    status,
    durationMs,
    errorCode: error.code,
    providerStatus: error.providerStatus,
    retryable: error.retryable,
    blockedByBilling: error.blockedByBilling,
  });
}

function makeSafeTelemetryEvent(event, checkedAt) {
  const status = Number.isFinite(event.status) ? Math.trunc(event.status) : 0;
  const durationMs = Number.isFinite(event.durationMs) ? Math.max(0, Math.trunc(event.durationMs)) : undefined;
  const providerStatus = Number.isFinite(event.providerStatus) ? Math.trunc(event.providerStatus) : undefined;
  const errorCode = cleanTelemetryToken(event.errorCode);

  return Object.fromEntries(
    Object.entries({
      timestamp: new Date(checkedAt).toISOString(),
      route: cleanTelemetryToken(event.route) ?? "unknown",
      method: cleanTelemetryToken(event.method) ?? "GET",
      path: event.path === lensPilotCreativeServerDefaults.creativePath
        ? lensPilotCreativeServerDefaults.creativePath
        : cleanTelemetryPath(event.path),
      status,
      outcome: status >= 200 && status < 300 ? "success" : "failure",
      durationMs,
      errorCode,
      providerStatus,
      retryable: typeof event.retryable === "boolean" ? event.retryable : undefined,
      blockedByBilling: typeof event.blockedByBilling === "boolean" ? event.blockedByBilling : undefined,
    }).filter(([, value]) => value !== undefined)
  );
}

function parseJSONResultBody(body) {
  if (typeof body !== "string") return undefined;
  try {
    return JSON.parse(body);
  } catch {
    return undefined;
  }
}

function cleanTelemetryToken(value) {
  const cleaned = cleanOptional(value);
  if (!cleaned) return undefined;
  const token = cleaned.toLowerCase().replace(/[^a-z0-9_.-]/g, "_").slice(0, 80);
  return token.length > 0 ? token : undefined;
}

function cleanTelemetryPath(path) {
  const cleaned = cleanOptional(path);
  if (!cleaned) return "/";
  return cleaned.startsWith("/") ? cleaned.slice(0, 96) : `/${cleaned}`.slice(0, 96);
}

function incrementCounter(record, key) {
  record[key] = (record[key] ?? 0) + 1;
}

function sortRecordByKey(record) {
  return Object.fromEntries(Object.entries(record).sort(([left], [right]) => left.localeCompare(right)));
}

function isSignedRequestFailureCode(code) {
  return [
    "signed_request_required",
    "signed_request_unconfigured",
    "invalid_signature_headers",
    "invalid_signature",
    "stale_signature",
    "replayed_request",
  ].includes(code);
}

export function makeLensPilotPhoneRequestSignature({
  secret,
  method,
  path,
  timestamp,
  requestId,
  body,
}) {
  const cleanedSecret = cleanOptional(secret);
  const cleanedRequestId = cleanSignatureRequestId(requestId);
  const cleanedTimestamp = cleanSignatureTimestamp(timestamp);
  if (!cleanedSecret || !cleanedRequestId || !cleanedTimestamp) {
    throw new Error("invalid_lenspilot_signature_input");
  }

  const canonical = makeLensPilotPhoneRequestSignatureCanonicalString({
    method,
    path,
    timestamp: cleanedTimestamp,
    requestId: cleanedRequestId,
    body,
  });
  const digest = createHmac("sha256", cleanedSecret)
    .update(canonical)
    .digest();

  return `v1=${toBase64URL(digest)}`;
}

function validateLensPilotSignedPhoneRequest({
  method,
  path,
  headers,
  body,
  config,
  replayGuard,
}) {
  const signature = headerValue(headers, "x-lenspilot-signature");
  const timestamp = headerValue(headers, "x-lenspilot-timestamp");
  const requestId = headerValue(headers, "x-lenspilot-request-id");
  const hasSignatureHeaders = Boolean(signature || timestamp || requestId);

  if (!config.signedRequestsRequired && !hasSignatureHeaders) {
    return { allowed: true };
  }
  if (!config.clientSigningSecret) {
    return {
      allowed: false,
      status: 503,
      code: "signed_request_unconfigured",
      message: "Creative API signed request verification is not configured.",
    };
  }
  if (!signature || !timestamp || !requestId) {
    return {
      allowed: false,
      status: 401,
      code: "signed_request_required",
      message: "Creative API requires a signed phone request.",
    };
  }

  const cleanedRequestId = cleanSignatureRequestId(requestId);
  const cleanedTimestamp = cleanSignatureTimestamp(timestamp);
  const actualSignature = cleanSignatureHeader(signature);
  if (!cleanedRequestId || !cleanedTimestamp || !actualSignature) {
    return {
      allowed: false,
      status: 401,
      code: "invalid_signature_headers",
      message: "Creative API signed request headers are invalid.",
    };
  }

  const timestampMs = signatureTimestampToMilliseconds(cleanedTimestamp);
  const now = typeof replayGuard.now === "function" ? replayGuard.now() : Date.now();
  if (Math.abs(now - timestampMs) > config.signatureToleranceMs) {
    return {
      allowed: false,
      status: 401,
      code: "stale_signature",
      message: "Creative API signed request is outside the allowed time window.",
    };
  }

  const expectedSignature = makeLensPilotPhoneRequestSignature({
    secret: config.clientSigningSecret,
    method,
    path,
    timestamp: cleanedTimestamp,
    requestId: cleanedRequestId,
    body,
  });
  if (!secureEqualSignature(actualSignature, expectedSignature)) {
    return {
      allowed: false,
      status: 401,
      code: "invalid_signature",
      message: "Creative API signed request verification failed.",
    };
  }

  const replayKey = makeSignatureReplayKey(cleanedRequestId, actualSignature);
  const replay = replayGuard.take(replayKey, timestampMs + config.signatureToleranceMs);
  if (!replay.allowed) {
    return {
      allowed: false,
      status: 401,
      code: "replayed_request",
      message: "Creative API signed request was already used.",
    };
  }

  return { allowed: true };
}

function makeLensPilotPhoneRequestSignatureCanonicalString({
  method,
  path,
  timestamp,
  requestId,
  body,
}) {
  return [
    "v1",
    String(method ?? "GET").toUpperCase(),
    normalizeSignaturePath(path),
    String(timestamp),
    String(requestId),
    sha256Hex(body ?? ""),
  ].join("\n");
}

function secureEqualSignature(actual, expected) {
  const actualToken = actual.replace(/^v1=/, "");
  const expectedToken = expected.replace(/^v1=/, "");
  const actualBuffer = Buffer.from(actualToken);
  const expectedBuffer = Buffer.from(expectedToken);
  return actualBuffer.length === expectedBuffer.length &&
    timingSafeEqual(actualBuffer, expectedBuffer);
}

function cleanSignatureHeader(value) {
  const cleaned = cleanOptional(value);
  if (!cleaned || !/^v1=[A-Za-z0-9_-]{32,128}$/.test(cleaned)) return undefined;
  return cleaned;
}

function cleanSignatureRequestId(value) {
  const cleaned = cleanOptional(value);
  if (!cleaned || !/^[A-Za-z0-9_.:-]{8,128}$/.test(cleaned)) return undefined;
  return cleaned;
}

function cleanSignatureTimestamp(value) {
  const cleaned = cleanOptional(String(value ?? ""));
  if (!cleaned || !/^\d{10,17}$/.test(cleaned)) return undefined;
  return cleaned;
}

function signatureTimestampToMilliseconds(timestamp) {
  const numeric = Number.parseInt(timestamp, 10);
  return timestamp.length <= 10 ? numeric * 1000 : numeric;
}

function normalizeSignaturePath(path) {
  const cleaned = cleanOptional(path);
  if (!cleaned) return "/";
  const withoutQuery = cleaned.split("?")[0];
  const withSlash = withoutQuery.startsWith("/") ? withoutQuery : `/${withoutQuery}`;
  return withSlash.replace(/\/+$/, "") || "/";
}

function makeSignatureReplayKey(requestId, signature) {
  return sha256Hex(`${requestId}\n${signature}`).slice(0, 64);
}

function sha256Hex(value) {
  return createHash("sha256").update(value).digest("hex");
}

function toBase64URL(buffer) {
  return Buffer.from(buffer)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function createMemoryReplayGuard({ windowMs, maxEntries, now }) {
  const seen = new Map();
  const safeWindowMs = Math.max(1_000, windowMs);
  const safeMaxEntries = Math.max(1, Math.min(50_000, maxEntries));

  return {
    now() {
      return now();
    },
    take(key, expiresAt) {
      const checkedAt = now();
      for (const [storedKey, storedExpiresAt] of seen) {
        if (storedExpiresAt <= checkedAt) {
          seen.delete(storedKey);
        }
      }

      if (seen.has(key)) {
        return { allowed: false };
      }

      seen.set(key, Math.max(checkedAt + safeWindowMs, expiresAt));
      while (seen.size > safeMaxEntries) {
        const oldestKey = seen.keys().next().value;
        seen.delete(oldestKey);
      }

      return { allowed: true };
    },
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

function parseBooleanOption(value, fallback) {
  if (typeof value === "boolean") return value;
  const cleaned = cleanOptional(value);
  if (!cleaned) return fallback;
  return !["0", "false", "no", "off"].includes(cleaned.toLowerCase());
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
      metricsPath: lensPilotCreativeServerDefaults.metricsPath,
      creativePath: lensPilotCreativeServerDefaults.creativePath,
    }));
  });
}
