const fs = require("node:fs");
const path = require("node:path");

const defaultAttempts = 30;
const defaultDelayMs = 20_000;
const defaultEndpointTimeoutMs = 30_000;

async function runLensPilotRenderDeploy(options = {}) {
  const config = makeLensPilotRenderDeployConfig(options);
  const deploy = await triggerRenderDeployHook(config);
  const readiness = await waitForProductionEndpoint(config);
  const ready = readiness.status === "ready";

  return {
    renderDeploy: true,
    status: ready ? "ready" : "not_ready",
    deploy,
    readiness,
  };
}

function makeLensPilotRenderDeployConfig(options = {}) {
  const environment = options.environment ?? process.env;
  const deployHookURL = cleanOptional(options.deployHookURL ?? environment.RENDER_DEPLOY_HOOK_URL);
  const creativeApiURL = cleanOptional(options.creativeApiURL ?? environment.LENSPILOT_CREATIVE_API_URL);
  const metricsToken = cleanOptional(options.metricsToken ?? environment.LENSPILOT_METRICS_TOKEN);

  if (!deployHookURL) throw new Error("missing_render_deploy_hook_url");
  if (!creativeApiURL) throw new Error("missing_lenspilot_creative_api_url");

  const parsedDeployHookURL = parseSecretURL(deployHookURL, "invalid_render_deploy_hook_url");
  const parsedCreativeApiURL = parseSecretURL(creativeApiURL, "invalid_lenspilot_creative_api_url");
  assertHTTPS(parsedDeployHookURL, "insecure_render_deploy_hook_url");

  return {
    fetchImpl: options.fetchImpl ?? globalThis.fetch,
    sleep: options.sleep ?? sleep,
    endpointCheckModule: options.endpointCheckModule,
    deployHookURL: parsedDeployHookURL,
    creativeApiURL: parsedCreativeApiURL,
    metricsToken,
    attempts: parsePositiveInteger(options.attempts ?? environment.LENSPILOT_RENDER_DEPLOY_CHECK_ATTEMPTS, defaultAttempts),
    delayMs: parsePositiveInteger(options.delayMs ?? environment.LENSPILOT_RENDER_DEPLOY_CHECK_DELAY_MS, defaultDelayMs),
    endpointTimeoutMs: parsePositiveInteger(
      options.endpointTimeoutMs ?? environment.LENSPILOT_ENDPOINT_CHECK_TIMEOUT_MS,
      defaultEndpointTimeoutMs
    ),
  };
}

async function triggerRenderDeployHook(config) {
  assertFetch(config.fetchImpl);
  const response = await config.fetchImpl(config.deployHookURL, {
    method: "POST",
  });
  const responseText = await response.text();
  const accepted = isAcceptedRenderDeployStatus(response.status);

  if (!accepted) {
    throw new Error(`render_deploy_hook_failed_${sanitizeStatus(response.status)}`);
  }

  return {
    triggered: true,
    httpStatus: response.status,
    deployId: extractDeployId(responseText),
  };
}

async function waitForProductionEndpoint(config) {
  const endpointCheck = config.endpointCheckModule ?? loadEndpointCheckModule();
  let lastReport = null;

  for (let attempt = 1; attempt <= config.attempts; attempt += 1) {
    lastReport = await endpointCheck.runLensPilotProductionEndpointCheck({
      apiURL: config.creativeApiURL.href,
      metricsToken: config.metricsToken,
      timeoutMs: config.endpointTimeoutMs,
      fetchImpl: config.fetchImpl,
    });

    if (lastReport.status === "ready") {
      return {
        status: "ready",
        attempts: attempt,
        productionEndpointCheck: lastReport,
      };
    }

    if (attempt < config.attempts) {
      await config.sleep(config.delayMs);
    }
  }

  return {
    status: "not_ready",
    attempts: config.attempts,
    productionEndpointCheck: lastReport,
  };
}

function loadEndpointCheckModule() {
  const moduleContext = { exports: {} };
  return Function(
    "module",
    "exports",
    "require",
    `${fs.readFileSync(path.join(__dirname, "check-production-endpoint.cjs"), "utf8")}
return module.exports;
`
  )(moduleContext, moduleContext.exports, require);
}

function extractDeployId(responseText) {
  try {
    const parsed = JSON.parse(responseText);
    return cleanOptional(parsed?.deploy?.id) ?? cleanOptional(parsed?.id) ?? null;
  } catch {
    return null;
  }
}

function isAcceptedRenderDeployStatus(status) {
  return status === 200 || status === 201 || status === 202;
}

function parseSecretURL(value, errorCode) {
  try {
    const url = new URL(value);
    if (url.username || url.password) throw new Error(errorCode);
    return url;
  } catch {
    throw new Error(errorCode);
  }
}

function assertHTTPS(url, errorCode) {
  if (url.protocol !== "https:") throw new Error(errorCode);
}

function assertFetch(fetchImpl) {
  if (typeof fetchImpl !== "function") throw new Error("fetch_unavailable");
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

function sanitizeStatus(status) {
  return Number.isFinite(status) ? Math.trunc(status) : "unknown";
}

function sleep(delayMs) {
  return new Promise((resolve) => setTimeout(resolve, delayMs));
}

if (require.main === module) {
  runLensPilotRenderDeploy()
    .then((report) => {
      console.log(JSON.stringify(report, null, 2));
      if (report.status !== "ready") {
        process.exitCode = 1;
      }
    })
    .catch((error) => {
      console.error(JSON.stringify({
        renderDeploy: true,
        status: "error",
        error: {
          code: String(error?.message ?? "render_deploy_failed")
            .replace(/[^a-z0-9_]/gi, "_")
            .toLowerCase()
            .slice(0, 80),
          message: "LensPilot Render deploy could not complete.",
        },
      }, null, 2));
      process.exitCode = 1;
    });
}

module.exports = {
  defaultAttempts,
  defaultDelayMs,
  defaultEndpointTimeoutMs,
  isAcceptedRenderDeployStatus,
  makeLensPilotRenderDeployConfig,
  runLensPilotRenderDeploy,
  triggerRenderDeployHook,
  waitForProductionEndpoint,
};
