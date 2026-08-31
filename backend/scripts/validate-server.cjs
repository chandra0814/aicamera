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

  console.log(JSON.stringify({
    creativeServer: true,
    healthPath: lensPilotCreativeServerDefaults.healthPath,
    readyPath: lensPilotCreativeServerDefaults.readyPath,
    creativePath: lensPilotCreativeServerDefaults.creativePath,
    rateLimited: true,
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
