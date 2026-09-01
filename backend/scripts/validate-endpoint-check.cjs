const http = require("node:http");
const fs = require("node:fs");

const checkerSource = fs.readFileSync("scripts/check-production-endpoint.cjs", "utf8");
const checkerModule = { exports: {} };
const {
  makeLensPilotEndpointCheckConfig,
  runLensPilotProductionEndpointCheck,
} = Function(
  "module",
  "exports",
  "require",
  `${checkerSource}
return module.exports;
`
)(checkerModule, checkerModule.exports, require);

main().catch((error) => {
  console.error(error);
  process.exit(1);
});

async function main() {
  await withProductionFixtureServer(async ({ baseURL, seen }) => {
    const report = await runLensPilotProductionEndpointCheck({
      environment: {
        LENSPILOT_CREATIVE_API_URL: `${baseURL}/v1/creative-interpretation`,
        LENSPILOT_METRICS_TOKEN: "metrics-token",
      },
    });
    const reportText = JSON.stringify(report);

    assert(report.status === "ready", "Production endpoint check should pass for safe ready metadata.");
    assert(report.metrics.checked === true, "Production endpoint check should probe metrics when a metrics token is supplied.");
    assert(seen.metricsAuthorization === "Bearer metrics-token", "Metrics probe should use the configured bearer token.");
    assert(!reportText.includes("metrics-token"), "Endpoint check report must not expose metrics tokens.");
    assert(!reportText.includes("sk-test"), "Endpoint check report must not expose OpenAI-looking secrets.");
    assert(report.checks.every((check) => check.status === "pass"), "Safe production fixture should pass every required check.");
  });

  await withProductionFixtureServer(async ({ baseURL }) => {
    const report = await runLensPilotProductionEndpointCheck({
      environment: {
        LENSPILOT_CREATIVE_API_URL: `${baseURL}/v1/creative-interpretation`,
      },
    });

    assert(report.status === "ready", "Metrics token should be optional for readiness when /ready already reports protected metrics.");
    assert(report.metrics.checked === false, "Metrics probe should be skipped without a local metrics token.");
    assert(report.metrics.reason === "metrics_token_not_provided", "Skipped metrics probe should explain the safe reason.");
  });

  await withUnsafeReadyServer(async ({ baseURL }) => {
    const report = await runLensPilotProductionEndpointCheck({
      environment: {
        LENSPILOT_CREATIVE_API_URL: `${baseURL}/v1/creative-interpretation`,
      },
    });
    const failedChecks = new Set(report.checks.filter((check) => check.status === "fail").map((check) => check.id));

    assert(report.status === "not_ready", "Production endpoint check should fail unsafe readiness metadata.");
    assert(failedChecks.has("phone_client_authorization"), "Unsafe readiness should fail phone auth.");
    assert(failedChecks.has("signed_phone_requests"), "Unsafe readiness should fail signed requests.");
    assert(failedChecks.has("production_safety_required"), "Unsafe readiness should fail missing production enforcement.");
    assert(failedChecks.has("cors_origin_policy"), "Unsafe readiness should fail wildcard CORS.");
    assert(failedChecks.has("secret_rotation_metadata"), "Unsafe readiness should fail missing rotation metadata.");
    assert(failedChecks.has("secret_rotation_window"), "Unsafe readiness should fail an over-wide rotation window.");
  });

  const localConfig = makeLensPilotEndpointCheckConfig({
    environment: {
      LENSPILOT_CREATIVE_API_URL: "http://127.0.0.1:8787/v1/creative-interpretation",
      LENSPILOT_ENDPOINT_CHECK_TIMEOUT_MS: "1500",
    },
    fetchImpl: async () => ({ status: 200, text: async () => "{}" }),
  });
  assert(localConfig.timeoutMs === 1500, "Endpoint check should honor positive timeout config.");
  assert(localConfig.endpoints.health.pathname === "/health", "Endpoint check should derive the health path from the creative route.");
  assert(localConfig.endpoints.ready.pathname === "/ready", "Endpoint check should derive the ready path from the creative route.");

  assertThrows(
    () => makeLensPilotEndpointCheckConfig({ environment: {}, fetchImpl: async () => ({}) }),
    "missing_lenspilot_creative_api_url",
    "Endpoint check should require a target API URL."
  );
  assertThrows(
    () => makeLensPilotEndpointCheckConfig({
      environment: {
        LENSPILOT_CREATIVE_API_URL: "http://api.lenspilot.example/v1/creative-interpretation",
      },
      fetchImpl: async () => ({}),
    }),
    "insecure_lenspilot_creative_api_url",
    "Endpoint check should reject non-local HTTP URLs."
  );
  assertThrows(
    () => makeLensPilotEndpointCheckConfig({
      environment: {
        LENSPILOT_CREATIVE_API_URL: "https://user:pass@api.lenspilot.example/v1/creative-interpretation",
      },
      fetchImpl: async () => ({}),
    }),
    "invalid_lenspilot_creative_api_url",
    "Endpoint check should reject credentialed URLs."
  );

  console.log(JSON.stringify({
    productionEndpointCheck: true,
    safeEndpoint: true,
    unsafeEndpointRejected: true,
    status: "passed",
  }, null, 2));
}

function productionPrivacy() {
  return {
    keepsOpenAIKeyOnServer: true,
    acceptsClientOpenAIKey: false,
    singlePhoneOnly: true,
    usesAuditedPayload: true,
    usesProviderHealthGate: true,
    storesRawPhoto: false,
    uploadsLiveCameraFrame: false,
    sendsPrivatePhoto: false,
    sendsIdentityData: false,
    sendsPreciseLocation: false,
    sendsRawLearningEvents: false,
    allowsGenerativeImageOutput: false,
  };
}

function productionReadyBody() {
  return {
    status: "ready",
    service: "lenspilot-creative-api",
    apiVersion: "2026-08-31",
    openAIConfigured: true,
    clientAuthorizationConfigured: true,
    clientSignatureConfigured: true,
    signedRequestsRequired: true,
    rateLimit: {
      windowMs: 60000,
      maxRequests: 30,
    },
    signedRequestPolicy: {
      toleranceMs: 300000,
      replayMaxEntries: 1000,
    },
    requestBody: {
      maxBytes: 65536,
    },
    telemetry: {
      metricsEnabled: true,
      metricsAuthorizationConfigured: true,
      maxRecentEvents: 100,
    },
    secretRotation: {
      required: true,
      ready: true,
      maxAgeDays: 90,
      failedRequiredChecks: [],
      warnings: [],
      checks: [
        {
          id: "rotation_window",
          status: "pass",
          required: true,
          configured: true,
          maxAgeDays: 90,
          message: "Rotation freshness window is 90 days.",
        },
        {
          id: "openai_api_key",
          status: "pass",
          required: true,
          configured: true,
          lastRotatedAt: "2026-08-15T00:00:00.000Z",
          ageDays: 17,
          message: "Server OpenAI key rotation metadata is fresh.",
        },
        {
          id: "phone_client_token",
          status: "pass",
          required: true,
          configured: true,
          lastRotatedAt: "2026-08-15T00:00:00.000Z",
          ageDays: 17,
          message: "Phone bearer token rotation metadata is fresh.",
        },
        {
          id: "phone_signing_secret",
          status: "pass",
          required: true,
          configured: true,
          lastRotatedAt: "2026-08-15T00:00:00.000Z",
          ageDays: 17,
          message: "Phone request-signing secret rotation metadata is fresh.",
        },
        {
          id: "metrics_token",
          status: "pass",
          required: true,
          configured: true,
          lastRotatedAt: "2026-08-15T00:00:00.000Z",
          ageDays: 17,
          message: "Metrics token rotation metadata is fresh.",
        },
      ],
    },
    cors: {
      allowedOriginsConfigured: 1,
      wildcardAllowed: false,
    },
    productionSafety: {
      required: true,
      ready: true,
      failedRequiredChecks: [],
    },
    privacy: productionPrivacy(),
  };
}

function productionMetricsBody() {
  return {
    service: "lenspilot-creative-api",
    apiVersion: "2026-08-31",
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
    privacy: productionPrivacy(),
    totals: {
      creativeRequests: 0,
    },
  };
}

async function withProductionFixtureServer(run) {
  const seen = {};
  return withJSONServer((request, response) => {
    if (request.url === "/health") {
      writeJSON(response, 200, {
        status: "ok",
        service: "lenspilot-creative-api",
        apiVersion: "2026-08-31",
        creativePath: "/v1/creative-interpretation",
        metricsPath: "/metrics",
        privacy: productionPrivacy(),
      });
      return;
    }

    if (request.url === "/ready") {
      writeJSON(response, 200, productionReadyBody());
      return;
    }

    if (request.url === "/metrics") {
      seen.metricsAuthorization = request.headers.authorization;
      writeJSON(response, 200, productionMetricsBody());
      return;
    }

    writeJSON(response, 404, { error: { code: "not_found" } });
  }, (baseURL) => run({ baseURL, seen }));
}

async function withUnsafeReadyServer(run) {
  return withJSONServer((request, response) => {
    if (request.url === "/health") {
      writeJSON(response, 200, {
        status: "ok",
        service: "lenspilot-creative-api",
        privacy: productionPrivacy(),
      });
      return;
    }

    if (request.url === "/ready") {
      writeJSON(response, 503, {
        status: "not_ready",
        service: "lenspilot-creative-api",
        openAIConfigured: true,
        clientAuthorizationConfigured: false,
        clientSignatureConfigured: false,
        signedRequestsRequired: false,
        rateLimit: {
          windowMs: 60000,
          maxRequests: 500,
        },
        signedRequestPolicy: {
          toleranceMs: 900000,
          replayMaxEntries: 5000,
        },
        requestBody: {
          maxBytes: 262144,
        },
        telemetry: {
          metricsEnabled: true,
          metricsAuthorizationConfigured: false,
        },
        secretRotation: {
          required: true,
          ready: false,
          maxAgeDays: 365,
          failedRequiredChecks: ["rotation_window", "phone_client_token", "phone_signing_secret", "metrics_token"],
          warnings: [],
          checks: [
            {
              id: "rotation_window",
              status: "fail",
              required: true,
              configured: true,
              maxAgeDays: 365,
              message: "Rotation freshness window must not exceed 90 days.",
            },
          ],
        },
        cors: {
          allowedOriginsConfigured: 1,
          wildcardAllowed: true,
        },
        productionSafety: {
          required: false,
          ready: false,
          failedRequiredChecks: ["phone_client_authorization", "signed_phone_requests"],
        },
        privacy: productionPrivacy(),
      });
      return;
    }

    writeJSON(response, 404, { error: { code: "not_found" } });
  }, (baseURL) => run({ baseURL }));
}

async function withJSONServer(handler, run) {
  const server = http.createServer(handler);
  await new Promise((resolve) => {
    server.listen(0, "127.0.0.1", resolve);
  });

  const address = server.address();
  const baseURL = `http://127.0.0.1:${address.port}`;
  try {
    await run(baseURL);
  } finally {
    await new Promise((resolve, reject) => {
      server.close((error) => error ? reject(error) : resolve());
    });
  }
}

function writeJSON(response, status, body) {
  response.writeHead(status, {
    "content-type": "application/json",
  });
  response.end(JSON.stringify(body));
}

function assertThrows(fn, expectedMessage, message) {
  try {
    fn();
  } catch (error) {
    assert(error?.message === expectedMessage, message);
    return;
  }
  throw new Error(message);
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}
