const fs = require("node:fs");
const path = require("node:path");

const deployModule = { exports: {} };
const deployExports = Function(
  "module",
  "exports",
  "require",
  "__dirname",
  "__filename",
  `${fs.readFileSync("scripts/deploy-render.cjs", "utf8")}
return module.exports;
`
)(
  deployModule,
  deployModule.exports,
  require,
  path.resolve(process.cwd(), "scripts"),
  path.resolve(process.cwd(), "scripts", "deploy-render.cjs")
);

const {
  isAcceptedRenderDeployStatus,
  makeLensPilotRenderDeployConfig,
  runLensPilotRenderDeploy,
} = deployExports;

main().catch((error) => {
  console.error(error);
  process.exit(1);
});

async function main() {
  assert(isAcceptedRenderDeployStatus(200), "Render deploy status 200 should be accepted.");
  assert(isAcceptedRenderDeployStatus(201), "Render deploy status 201 should be accepted.");
  assert(isAcceptedRenderDeployStatus(202), "Render deploy status 202 should be accepted.");
  assert(!isAcceptedRenderDeployStatus(401), "Render deploy status 401 should fail.");

  assertThrows(
    () => makeLensPilotRenderDeployConfig({ environment: {} }),
    "missing_render_deploy_hook_url",
    "Render deploy config should require the deploy hook URL."
  );
  assertThrows(
    () => makeLensPilotRenderDeployConfig({
      environment: {
        RENDER_DEPLOY_HOOK_URL: "https://api.render.com/deploy/srv_test?key=secret",
      },
    }),
    "missing_lenspilot_creative_api_url",
    "Render deploy config should require the Creative API URL."
  );
  assertThrows(
    () => makeLensPilotRenderDeployConfig({
      environment: {
        RENDER_DEPLOY_HOOK_URL: "http://api.render.com/deploy/srv_test?key=secret",
        LENSPILOT_CREATIVE_API_URL: "https://lenspilot.example/v1/creative-interpretation",
      },
    }),
    "insecure_render_deploy_hook_url",
    "Render deploy hook should require HTTPS."
  );

  const report = await runLensPilotRenderDeploy({
    environment: {
      RENDER_DEPLOY_HOOK_URL: "https://api.render.com/deploy/srv_test?key=secret",
      LENSPILOT_CREATIVE_API_URL: "https://lenspilot.example/v1/creative-interpretation",
      LENSPILOT_METRICS_TOKEN: "metrics-token",
    },
    fetchImpl: makeFakeFetch(),
    sleep: async () => {},
    attempts: 2,
    delayMs: 1,
    endpointTimeoutMs: 1000,
  });

  const reportText = JSON.stringify(report);
  assert(report.status === "ready", "Render deploy should pass when endpoint readiness passes.");
  assert(report.deploy.triggered === true, "Render deploy should trigger the hook.");
  assert(report.deploy.httpStatus === 200, "Render deploy should record safe hook status.");
  assert(report.deploy.deployId === "dep_fixture", "Render deploy should capture a safe deploy id.");
  assert(report.readiness.status === "ready", "Render deploy should report endpoint readiness.");
  assert(report.readiness.attempts === 1, "Render deploy should stop polling when ready.");
  assert(!reportText.includes("key=secret"), "Render deploy output must not include the deploy hook secret.");
  assert(!reportText.includes("metrics-token"), "Render deploy output must not include the metrics token.");

  console.log(JSON.stringify({
    renderDeploy: true,
    hookTrigger: true,
    readinessPolling: true,
    secretValuesPrinted: false,
    status: "passed",
  }, null, 2));
}

function makeFakeFetch() {
  return async (url, options = {}) => {
    const parsedURL = new URL(url);
    if (parsedURL.hostname === "api.render.com") {
      return textResponse(200, JSON.stringify({
        deploy: {
          id: "dep_fixture",
        },
      }));
    }
    if (parsedURL.pathname === "/health") {
      return textResponse(200, JSON.stringify({
        status: "ok",
        service: "lenspilot-creative-api",
        privacy: safePrivacy(),
      }));
    }
    if (parsedURL.pathname === "/ready") {
      return textResponse(200, JSON.stringify({
        status: "ready",
        service: "lenspilot-creative-api",
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
        },
        secretRotation: {
          ready: true,
          failedRequiredChecks: [],
          maxAgeDays: 90,
        },
        cors: {
          wildcardAllowed: false,
        },
        productionSafety: {
          required: true,
          ready: true,
          failedRequiredChecks: [],
        },
        privacy: safePrivacy(),
      }));
    }
    if (parsedURL.pathname === "/metrics" && options.headers?.authorization === "Bearer metrics-token") {
      return textResponse(200, JSON.stringify({
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
        privacy: safePrivacy(),
      }));
    }
    return textResponse(404, JSON.stringify({
      error: {
        code: "not_found",
      },
    }));
  };
}

function safePrivacy() {
  return {
    singlePhoneOnly: true,
    acceptsClientOpenAIKey: false,
    uploadsLiveCameraFrame: false,
    sendsPrivatePhoto: false,
    sendsIdentityData: false,
    sendsPreciseLocation: false,
    sendsRawLearningEvents: false,
  };
}

function textResponse(status, body) {
  return {
    status,
    async text() {
      return body;
    },
  };
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
