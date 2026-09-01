const defaultEndpointPaths = {
  health: "/health",
  ready: "/ready",
  metrics: "/metrics",
  creative: "/v1/creative-interpretation",
};

async function runLensPilotProductionEndpointCheck(options = {}) {
  const config = makeLensPilotEndpointCheckConfig(options);
  const checks = [];

  const health = await fetchJSON(config.endpoints.health, config);
  addCheck(checks, "health_http_200", health.statusCode === 200, "Health endpoint returns HTTP 200.");
  addCheck(checks, "health_service_identity", health.body?.service === "lenspilot-creative-api", "Health endpoint identifies the LensPilot Creative API.");
  addSinglePhonePrivacyChecks(checks, "health", health.body?.privacy);

  const ready = await fetchJSON(config.endpoints.ready, config);
  const readyBody = ready.body ?? {};
  const productionSafety = readyBody.productionSafety ?? {};
  const secretRotation = readyBody.secretRotation ?? {};
  addCheck(checks, "ready_http_200", ready.statusCode === 200, "Ready endpoint returns HTTP 200.");
  addCheck(checks, "ready_status", readyBody.status === "ready", "Ready endpoint reports ready status.");
  addCheck(checks, "server_openai_key", readyBody.openAIConfigured === true, "Server-side OpenAI key is configured.");
  addCheck(checks, "phone_client_authorization", readyBody.clientAuthorizationConfigured === true, "Phone bearer authorization is configured.");
  addCheck(
    checks,
    "signed_phone_requests",
    readyBody.clientSignatureConfigured === true && readyBody.signedRequestsRequired === true,
    "Signed phone requests are configured and required."
  );
  addCheck(
    checks,
    "production_safety_required",
    productionSafety.required === true,
    "Production safety enforcement is enabled."
  );
  addCheck(
    checks,
    "production_safety_ready",
    productionSafety.ready === true && Array.isArray(productionSafety.failedRequiredChecks) && productionSafety.failedRequiredChecks.length === 0,
    "Production safety preflight is passing."
  );
  addCheck(
    checks,
    "cors_origin_policy",
    readyBody.cors?.wildcardAllowed === false,
    "CORS does not allow wildcard browser origins."
  );
  addCheck(
    checks,
    "request_body_cap",
    Number.isFinite(readyBody.requestBody?.maxBytes) && readyBody.requestBody.maxBytes <= 64 * 1024,
    "Request body cap is bounded for production."
  );
  addCheck(
    checks,
    "rate_limit_policy",
    Number.isFinite(readyBody.rateLimit?.windowMs) &&
      readyBody.rateLimit.windowMs > 0 &&
      Number.isFinite(readyBody.rateLimit?.maxRequests) &&
      readyBody.rateLimit.maxRequests > 0 &&
      readyBody.rateLimit.maxRequests <= 120,
    "Rate limit policy is bounded for production."
  );
  addCheck(
    checks,
    "signature_window",
    Number.isFinite(readyBody.signedRequestPolicy?.toleranceMs) &&
      readyBody.signedRequestPolicy.toleranceMs > 0 &&
      readyBody.signedRequestPolicy.toleranceMs <= 5 * 60 * 1000,
    "Signed request clock window is bounded."
  );
  addCheck(
    checks,
    "signature_replay_cache",
    Number.isFinite(readyBody.signedRequestPolicy?.replayMaxEntries) &&
      readyBody.signedRequestPolicy.replayMaxEntries > 0 &&
      readyBody.signedRequestPolicy.replayMaxEntries <= 1000,
    "Signed request replay cache is bounded."
  );
  addCheck(
    checks,
    "metrics_authorization_or_disabled",
    readyBody.telemetry?.metricsEnabled === false || readyBody.telemetry?.metricsAuthorizationConfigured === true,
    "Metrics are disabled or protected by bearer authorization."
  );
  addCheck(
    checks,
    "secret_rotation_metadata",
    secretRotation.ready === true &&
      Array.isArray(secretRotation.failedRequiredChecks) &&
      secretRotation.failedRequiredChecks.length === 0,
    "Required secret rotation metadata is fresh."
  );
  addCheck(
    checks,
    "secret_rotation_window",
    Number.isFinite(secretRotation.maxAgeDays) &&
      secretRotation.maxAgeDays > 0 &&
      secretRotation.maxAgeDays <= 90,
    "Secret rotation freshness window is bounded."
  );
  addSinglePhonePrivacyChecks(checks, "ready", readyBody.privacy);

  const metrics = await maybeCheckMetrics(config, readyBody, checks);
  const status = checks.some((check) => check.status === "fail") ? "not_ready" : "ready";

  return {
    productionEndpointCheck: true,
    service: "lenspilot-creative-api",
    status,
    target: {
      origin: config.baseURL.origin,
      paths: {
        health: config.endpoints.health.pathname,
        ready: config.endpoints.ready.pathname,
        metrics: config.endpoints.metrics.pathname,
        creative: config.endpoints.creative.pathname,
      },
    },
    checks,
    metrics,
  };
}

function makeLensPilotEndpointCheckConfig(options = {}) {
  const environment = options.environment ?? process.env;
  const timeoutMs = parsePositiveInteger(
    options.timeoutMs ?? environment.LENSPILOT_ENDPOINT_CHECK_TIMEOUT_MS,
    8000
  );
  const fetchImpl = options.fetchImpl ?? globalThis.fetch;
  if (typeof fetchImpl !== "function") {
    throw new Error("fetch_unavailable");
  }

  const rawURL = cleanOptional(
    options.apiURL ??
      environment.LENSPILOT_CREATIVE_API_URL ??
      environment.LENSPILOT_CREATIVE_API_BASE_URL
  );
  if (!rawURL) {
    throw new Error("missing_lenspilot_creative_api_url");
  }

  const creativeURL = parseURL(rawURL);
  assertHTTPSOrLocal(creativeURL);
  const baseURL = deriveBaseURL(creativeURL, defaultEndpointPaths.creative);

  return {
    fetchImpl,
    timeoutMs,
    metricsToken: cleanOptional(options.metricsToken ?? environment.LENSPILOT_METRICS_TOKEN),
    baseURL,
    endpoints: {
      health: endpointURL(baseURL, defaultEndpointPaths.health),
      ready: endpointURL(baseURL, defaultEndpointPaths.ready),
      metrics: endpointURL(baseURL, defaultEndpointPaths.metrics),
      creative: endpointURL(baseURL, defaultEndpointPaths.creative),
    },
  };
}

async function maybeCheckMetrics(config, readyBody, checks) {
  if (readyBody.telemetry?.metricsEnabled === false) {
    return {
      checked: false,
      reason: "metrics_disabled",
    };
  }

  if (!config.metricsToken) {
    return {
      checked: false,
      reason: "metrics_token_not_provided",
    };
  }

  const metrics = await fetchJSON(config.endpoints.metrics, config, {
    authorization: `Bearer ${config.metricsToken}`,
  });
  addCheck(checks, "metrics_http_200", metrics.statusCode === 200, "Metrics endpoint accepts the configured metrics token.");
  addCheck(checks, "metrics_retention_boundary", hasSafeMetricsRetention(metrics.body?.retention), "Metrics retention excludes raw user/private data.");
  addSinglePhonePrivacyChecks(checks, "metrics", metrics.body?.privacy);

  return {
    checked: true,
    statusCode: metrics.statusCode,
    retentionSafe: hasSafeMetricsRetention(metrics.body?.retention),
  };
}

function addSinglePhonePrivacyChecks(checks, prefix, privacy) {
  addCheck(checks, `${prefix}_single_phone_privacy`, privacy?.singlePhoneOnly === true, `${prefix} privacy reports single-phone operation.`);
  addCheck(checks, `${prefix}_rejects_client_openai_key`, privacy?.acceptsClientOpenAIKey === false, `${prefix} privacy rejects client-supplied OpenAI keys.`);
  addCheck(checks, `${prefix}_no_raw_camera_frame`, privacy?.uploadsLiveCameraFrame === false, `${prefix} privacy blocks raw live camera frames.`);
  addCheck(checks, `${prefix}_no_private_photo`, privacy?.sendsPrivatePhoto === false, `${prefix} privacy blocks private photo upload.`);
  addCheck(checks, `${prefix}_no_identity_data`, privacy?.sendsIdentityData === false, `${prefix} privacy blocks identity data.`);
  addCheck(checks, `${prefix}_no_precise_location`, privacy?.sendsPreciseLocation === false, `${prefix} privacy blocks precise location.`);
  addCheck(checks, `${prefix}_no_raw_learning_events`, privacy?.sendsRawLearningEvents === false, `${prefix} privacy blocks raw learning events.`);
}

function hasSafeMetricsRetention(retention) {
  return retention?.storesRawRequestBody === false &&
    retention?.storesPromptText === false &&
    retention?.storesClientIP === false &&
    retention?.storesAuthorizationHeader === false &&
    retention?.storesRawPhoto === false &&
    retention?.storesRawLearningEvents === false &&
    retention?.storesIdentityData === false &&
    retention?.storesPreciseLocation === false;
}

async function fetchJSON(url, config, headers = {}) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), config.timeoutMs);
  try {
    const response = await config.fetchImpl(url, {
      method: "GET",
      headers: {
        accept: "application/json",
        ...headers,
      },
      signal: controller.signal,
    });
    const text = await response.text();
    return {
      statusCode: response.status,
      body: parseJSON(text),
    };
  } catch (error) {
    return {
      statusCode: 0,
      body: null,
      errorCode: error?.name === "AbortError" ? "request_timeout" : "request_failed",
    };
  } finally {
    clearTimeout(timeout);
  }
}

function parseJSON(text) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function addCheck(checks, id, passed, message) {
  checks.push({
    id,
    status: passed ? "pass" : "fail",
    message,
  });
}

function deriveBaseURL(creativeURL, creativePath) {
  const normalizedCreativePath = normalizePath(creativePath);
  const normalizedURLPath = normalizePath(creativeURL.pathname);
  let basePath = "/";
  if (normalizedURLPath.endsWith(normalizedCreativePath)) {
    basePath = normalizedURLPath.slice(0, normalizedURLPath.length - normalizedCreativePath.length) || "/";
  } else if (normalizedURLPath !== "/") {
    basePath = normalizedURLPath;
  }

  const base = new URL(creativeURL.origin);
  base.pathname = normalizeDirectoryPath(basePath);
  return base;
}

function endpointURL(baseURL, endpointPath) {
  return new URL(endpointPath.replace(/^\/+/, ""), baseURL);
}

function parseURL(value) {
  try {
    const url = new URL(value);
    if (url.username || url.password) {
      throw new Error("credentialed_url_rejected");
    }
    url.search = "";
    url.hash = "";
    return url;
  } catch {
    throw new Error("invalid_lenspilot_creative_api_url");
  }
}

function assertHTTPSOrLocal(url) {
  const scheme = url.protocol.replace(":", "").toLowerCase();
  const host = url.hostname.toLowerCase();
  const localHosts = new Set(["localhost", "127.0.0.1", "::1", "[::1]"]);
  if (scheme !== "https" && !(scheme === "http" && localHosts.has(host))) {
    throw new Error("insecure_lenspilot_creative_api_url");
  }
}

function normalizePath(path) {
  const cleaned = cleanOptional(path) ?? "/";
  const withSlash = cleaned.startsWith("/") ? cleaned : `/${cleaned}`;
  return withSlash.replace(/\/+$/, "") || "/";
}

function normalizeDirectoryPath(path) {
  const normalized = normalizePath(path);
  return normalized === "/" ? "/" : `${normalized}/`;
}

function parsePositiveInteger(value, fallback) {
  const parsed = Number.parseInt(String(value ?? ""), 10);
  return Number.isFinite(parsed) && parsed > 0 ? Math.trunc(parsed) : fallback;
}

function cleanOptional(value) {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

if (require.main === module) {
  runLensPilotProductionEndpointCheck()
    .then((report) => {
      console.log(JSON.stringify(report, null, 2));
      if (report.status !== "ready") {
        process.exitCode = 1;
      }
    })
    .catch((error) => {
      console.error(JSON.stringify({
        productionEndpointCheck: true,
        status: "error",
        error: {
          code: sanitizeErrorCode(error?.message),
          message: "LensPilot production endpoint check could not run.",
        },
      }, null, 2));
      process.exitCode = 1;
    });
}

function sanitizeErrorCode(value) {
  const cleaned = cleanOptional(value) ?? "endpoint_check_failed";
  return cleaned.replace(/[^a-z0-9_]/gi, "_").toLowerCase().slice(0, 80);
}

module.exports = {
  defaultEndpointPaths,
  makeLensPilotEndpointCheckConfig,
  runLensPilotProductionEndpointCheck,
};
