const fs = require("node:fs");
const http = require("node:http");
const { pathToFileURL } = require("node:url");

const apiSource = fs
  .readFileSync("api/creative-interpretation.mjs", "utf8")
  .replace(/^export /gm, "");
const apiModule = Function(`${apiSource}
return {
  createLensPilotCreativeInterpretationApi,
  lensPilotCreativeInterpretationApiDefaults,
  lensPilotCreativeInterpretationApiPrivacy,
};
`)();

const serverSource = fs
  .readFileSync("server.mjs", "utf8")
  .replace(/^import http from "node:http";\r?\n/, "")
  .replace(/^import \{ pathToFileURL \} from "node:url";\r?\n/, "")
  .replace(/import \{\r?\n[\s\S]*?\} from "\.\/api\/creative-interpretation\.mjs";\r?\n/, "")
  .replace(/^export /gm, "")
  .replace(/import\.meta\.url/g, "\"file:///lenspilot/backend/server.mjs\"");

const serverModule = Function(
  "http",
  "pathToFileURL",
  "createLensPilotCreativeInterpretationApi",
  "lensPilotCreativeInterpretationApiDefaults",
  "lensPilotCreativeInterpretationApiPrivacy",
  `${serverSource}
return {
  createLensPilotCreativeHTTPServer,
  describeLensPilotCreativeServerConfig,
  lensPilotCreativeServerDefaults,
};
`
)(
  http,
  pathToFileURL,
  apiModule.createLensPilotCreativeInterpretationApi,
  apiModule.lensPilotCreativeInterpretationApiDefaults,
  apiModule.lensPilotCreativeInterpretationApiPrivacy
);

const {
  createLensPilotCreativeHTTPServer,
  describeLensPilotCreativeServerConfig,
  lensPilotCreativeServerDefaults,
} = serverModule;
const {
  lensPilotCreativeInterpretationApiDefaults,
} = apiModule;

const safePayloadAudit = {
  safeToSend: true,
  deniedReasons: [],
  blockedTermsDetected: [],
  allowedInputCount: 4,
  summaryCount: 3,
  suggestionCount: 3,
};

const safeApiRequest = {
  apiVersion: lensPilotCreativeInterpretationApiDefaults.apiVersion,
  request: {
    planId: "creative_plan_server_fixture",
    provider: "online_reasoning",
    inputSummary: [
      "Prompt intent: cinematic portrait with warm side light.",
      "ShotSpec summary: portrait, environmental framing, clean background.",
      "Public reference summary: soft side light and calm editorial composition.",
    ],
    suggestionBriefs: [
      "Lighting: Turn the subject toward softer side light.",
      "Composition: Keep the background edge clean behind the shoulders.",
      "Safety: Stay Capture-Realistic and guide only what the phone can capture.",
    ],
    allowedInputs: [
      "prompt_text",
      "shot_spec_summary",
      "learned_preference_summary",
      "public_reference_summary",
    ],
    mustNotSend: [
      "raw_live_camera_feed",
      "private_photo",
      "face_identity",
      "precise_location_without_consent",
      "raw_learning_events",
    ],
    maxResponseWords: 64,
    payloadAudit: safePayloadAudit,
    privacy: {
      singlePhoneOnly: true,
      requiresUserConsent: true,
      sendsRawCameraFrame: false,
      sendsPrivatePhoto: false,
      sendsIdentityData: false,
      sendsPreciseLocation: false,
      sendsRawLearningEvents: false,
      allowsGenerativeOutput: false,
    },
  },
  healthGate: {
    canRunProvider: true,
    deniedReasons: [],
    providerHealthStatus: "available",
    publicReferenceCount: 3,
    payloadAudit: safePayloadAudit,
    privacy: {
      singlePhoneOnly: true,
      requiresUserConsent: true,
      sendsRawCameraFrame: false,
      sendsPrivatePhoto: false,
      sendsIdentityData: false,
      sendsPreciseLocation: false,
      sendsRawLearningEvents: false,
    },
  },
  client: {
    platform: "ios",
    appVersion: "0.1.0",
    requestId: "server-fixture-001",
  },
};

main().catch((error) => {
  console.error(error);
  process.exit(1);
});

async function main() {
  const safeProductionConfig = describeLensPilotCreativeServerConfig({
    openAIAPIKey: "sk-test-server-side",
    expectedClientToken: "client-token",
    allowedOrigins: ["https://app.lenspilot.example"],
    requireProductionSafety: true,
    rateLimitMaxRequests: 30,
    maxRequestBytes: 64 * 1024,
  });
  assert(safeProductionConfig.productionSafety.ready === true, "Production preflight should pass for protected configuration.");
  assert(safeProductionConfig.productionSafety.failedRequiredChecks.length === 0, "Protected production configuration should not report failures.");
  assert(!JSON.stringify(safeProductionConfig).includes("sk-test"), "Production preflight must not expose secrets.");

  const unsafeProductionConfig = describeLensPilotCreativeServerConfig({
    openAIAPIKey: "sk-test-server-side",
    allowedOrigins: ["*"],
    requireProductionSafety: true,
    rateLimitMaxRequests: 500,
    maxRequestBytes: 256 * 1024,
  });
  assert(unsafeProductionConfig.productionSafety.ready === false, "Production preflight should fail unsafe configuration.");
  assert(
    unsafeProductionConfig.productionSafety.failedRequiredChecks.includes("phone_client_authorization"),
    "Production preflight should require phone client authorization."
  );
  assert(
    unsafeProductionConfig.productionSafety.failedRequiredChecks.includes("cors_origin_policy"),
    "Production preflight should reject wildcard CORS."
  );
  assert(
    unsafeProductionConfig.productionSafety.failedRequiredChecks.includes("request_body_cap"),
    "Production preflight should enforce the request body cap."
  );
  assert(
    unsafeProductionConfig.productionSafety.failedRequiredChecks.includes("rate_limit_policy"),
    "Production preflight should enforce bounded rate limits."
  );

  await withServer(
    {
      openAIAPIKey: "sk-test-server-side",
      expectedClientToken: "client-token",
      allowedOrigins: ["https://app.lenspilot.example"],
      rateLimitMaxRequests: 10,
      fetchImpl: async () => ({
        ok: true,
        status: 200,
        async json() {
          return {
            status: "completed",
            output_text: JSON.stringify({
              headline: "Server Runtime Brief",
              guidance: [
                "Turn the subject toward the softer side light.",
                "Keep the phone steady and preserve the clean background edge.",
              ],
            }),
          };
        },
      }),
    },
    async (baseURL) => {
      const health = await fetch(`${baseURL}${lensPilotCreativeServerDefaults.healthPath}`);
      const healthBody = await health.json();
      assert(health.status === 200, "Health route should return 200.");
      assert(healthBody.status === "ok", "Health route should return ok status.");
      assert(!JSON.stringify(healthBody).includes("sk-test"), "Health route must not expose secrets.");

      const ready = await fetch(`${baseURL}${lensPilotCreativeServerDefaults.readyPath}`);
      const readyBody = await ready.json();
      assert(ready.status === 200, "Ready route should return 200 when the server key is configured.");
      assert(readyBody.openAIConfigured === true, "Ready route should report configured OpenAI state.");
      assert(readyBody.clientAuthorizationConfigured === true, "Ready route should report client auth state.");
      assert(readyBody.productionSafety.ready === true, "Ready route should include passing production safety metadata.");

      const preflight = await fetch(`${baseURL}${lensPilotCreativeServerDefaults.creativePath}`, {
        method: "OPTIONS",
        headers: {
          origin: "https://app.lenspilot.example",
        },
      });
      assert(preflight.status === 204, "CORS preflight should return 204.");
      assert(
        preflight.headers.get("access-control-allow-origin") === "https://app.lenspilot.example",
        "CORS should echo configured allowed origins."
      );

      const unauthorized = await fetch(`${baseURL}${lensPilotCreativeServerDefaults.creativePath}`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
        },
        body: JSON.stringify(safeApiRequest),
      });
      assert(unauthorized.status === 401, "Creative route should enforce configured client authorization.");

      const creative = await fetch(`${baseURL}${lensPilotCreativeServerDefaults.creativePath}`, {
        method: "POST",
        headers: {
          authorization: "Bearer client-token",
          "content-type": "application/json",
          origin: "https://app.lenspilot.example",
        },
        body: JSON.stringify(safeApiRequest),
      });
      const creativeBody = await creative.json();
      assert(creative.status === 200, "Creative route should return provider output for safe requests.");
      assert(creativeBody.result.headline === "Server Runtime Brief", "Creative route should return provider headline.");
      assert(creative.headers.get("x-ratelimit-limit") === "10", "Creative route should include rate limit headers.");
      assert(!JSON.stringify(creativeBody).includes("sk-test"), "Creative route must not expose secrets.");

      const notFound = await fetch(`${baseURL}/unknown`);
      assert(notFound.status === 404, "Unknown routes should return 404.");
    }
  );

  await withServer(
    {
      openAIAPIKey: "sk-test-server-side",
      rateLimitMaxRequests: 1,
      fetchImpl: async () => ({
        ok: true,
        status: 200,
        async json() {
          return {
            status: "completed",
            output_text: JSON.stringify({
              headline: "Rate Limit Fixture",
              guidance: [
                "Use softer side light.",
                "Keep the phone steady.",
              ],
            }),
          };
        },
      }),
    },
    async (baseURL) => {
      const first = await fetch(`${baseURL}${lensPilotCreativeServerDefaults.creativePath}`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-forwarded-for": "198.51.100.10",
        },
        body: JSON.stringify(safeApiRequest),
      });
      assert(first.status === 200, "First request under the limit should pass.");

      const second = await fetch(`${baseURL}${lensPilotCreativeServerDefaults.creativePath}`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-forwarded-for": "198.51.100.10",
        },
        body: JSON.stringify(safeApiRequest),
      });
      assert(second.status === 429, "Second request over the limit should be rate-limited.");
      assert(second.headers.get("retry-after") !== null, "Rate-limited responses should include retry-after.");
    }
  );

  await withServer(
    {
      openAIAPIKey: "",
    },
    async (baseURL) => {
      const ready = await fetch(`${baseURL}${lensPilotCreativeServerDefaults.readyPath}`);
      const readyBody = await ready.json();
      assert(ready.status === 503, "Ready route should return 503 when the server key is missing.");
      assert(readyBody.openAIConfigured === false, "Ready route should report missing OpenAI configuration.");
    }
  );

  await withServer(
    {
      openAIAPIKey: "sk-test-server-side",
      requireProductionSafety: true,
      allowedOrigins: ["*"],
      rateLimitMaxRequests: 500,
      maxRequestBytes: 256 * 1024,
    },
    async (baseURL) => {
      const ready = await fetch(`${baseURL}${lensPilotCreativeServerDefaults.readyPath}`);
      const readyBody = await ready.json();
      assert(ready.status === 503, "Ready route should fail unsafe production configuration.");
      assert(readyBody.productionSafety.ready === false, "Unsafe production config should report not ready.");
      assert(
        readyBody.productionSafety.failedRequiredChecks.includes("phone_client_authorization"),
        "Ready route should report missing phone client authorization."
      );
      assert(
        readyBody.productionSafety.failedRequiredChecks.includes("cors_origin_policy"),
        "Ready route should report wildcard CORS as unsafe for production."
      );
    }
  );

  await withServer(
    {
      openAIAPIKey: "sk-test-server-side",
      fetchImpl: async () => ({
        ok: false,
        status: 429,
        async json() {
          return {
            error: {
              type: "insufficient_quota",
              code: "credit_balance_exhausted",
              message: "Provider billing details are not forwarded.",
            },
          };
        },
      }),
    },
    async (baseURL) => {
      const quotaBlocked = await fetch(`${baseURL}${lensPilotCreativeServerDefaults.creativePath}`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
        },
        body: JSON.stringify(safeApiRequest),
      });
      const quotaBlockedBody = await quotaBlocked.json();
      assert(quotaBlocked.status === 502, "Provider failures should stay behind the LensPilot API boundary.");
      assert(quotaBlockedBody.error.code === "openai_credit_balance_exhausted", "Server should classify exhausted provider credits.");
      assert(quotaBlockedBody.error.providerStatus === 429, "Server should expose only the provider status code.");
      assert(quotaBlockedBody.error.providerErrorCode === "credit_balance_exhausted", "Server should expose sanitized provider error code.");
      assert(quotaBlockedBody.error.providerErrorType === "insufficient_quota", "Server should expose sanitized provider error type.");
      assert(quotaBlockedBody.error.blockedByBilling === true, "Server should mark billing-blocked provider failures.");
      assert(!JSON.stringify(quotaBlockedBody).includes("sk-test"), "Classified provider errors must not leak secrets.");
    }
  );

  console.log(JSON.stringify({
    creativeServer: true,
    healthPath: lensPilotCreativeServerDefaults.healthPath,
    readyPath: lensPilotCreativeServerDefaults.readyPath,
    creativePath: lensPilotCreativeServerDefaults.creativePath,
    rateLimited: true,
    productionPreflight: true,
    status: "passed",
  }, null, 2));
}

async function withServer(options, run) {
  const server = createLensPilotCreativeHTTPServer({
    ...options,
    host: "127.0.0.1",
    port: 0,
  });

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

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}
