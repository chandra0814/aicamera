const fs = require("node:fs");
const apiSource = fs
  .readFileSync("../../backend/api/creative-interpretation.mjs", "utf8")
  .replace(/^export /gm, "");

const apiModule = Function(`${apiSource}
return {
  createLensPilotCreativeInterpretationApi,
  isLensPilotCreativeInterpretationApiRequestSafe,
  lensPilotCreativeInterpretationApiDefaults,
};
`)();

const {
  createLensPilotCreativeInterpretationApi,
  isLensPilotCreativeInterpretationApiRequestSafe,
  lensPilotCreativeInterpretationApiDefaults,
} = apiModule;

const safePrivacy = {
  singlePhoneOnly: true,
  requiresUserConsent: true,
  sendsRawCameraFrame: false,
  sendsPrivatePhoto: false,
  sendsIdentityData: false,
  sendsPreciseLocation: false,
  sendsRawLearningEvents: false,
  allowsGenerativeOutput: false,
};

const safePayloadAudit = {
  safeToSend: true,
  deniedReasons: [],
  blockedTermsDetected: [],
  allowedInputCount: 4,
  summaryCount: 3,
  suggestionCount: 3,
};

const safeRequest = {
  planId: "creative_plan_backend_fixture",
  provider: "online_reasoning",
  inputSummary: [
    "Prompt intent: cinematic luxury portrait.",
    "ShotSpec summary: portrait, environmental framing, clean background.",
    "Public reference summary: warm side light and calm editorial composition.",
  ],
  suggestionBriefs: [
    "Lighting: Turn the subject toward the softer side light.",
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
  privacy: safePrivacy,
};

const safeHealthGate = {
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
};

const safeApiRequest = {
  apiVersion: lensPilotCreativeInterpretationApiDefaults.apiVersion,
  request: safeRequest,
  healthGate: safeHealthGate,
  client: {
    platform: "ios",
    appVersion: "0.1.0",
    requestId: "creative-api-fixture-001",
  },
};

assert(
  isLensPilotCreativeInterpretationApiRequestSafe(safeApiRequest),
  "Creative API fixture should satisfy the mobile-safe request contract."
);

const fetchCalls = [];
const api = createLensPilotCreativeInterpretationApi({
  openAIAPIKey: "sk-test-server-side",
  expectedClientToken: "client-token",
  now: () => "2026-08-31T00:00:00.000Z",
  fetchImpl: async (url, options) => {
    fetchCalls.push({ url, options });
    return {
      ok: true,
      status: 200,
      async json() {
        return {
          status: "completed",
          output_text: JSON.stringify({
            headline: "Server-Safe Creative Brief",
            guidance: [
              "Turn the subject toward the softer side light.",
              "Keep the phone steady and hold the clean background edge.",
            ],
          }),
        };
      },
    };
  },
});

api.handle({
  method: "POST",
  headers: {
    "content-type": "application/json",
    authorization: "Bearer client-token",
  },
  body: JSON.stringify(safeApiRequest),
}).then(async (success) => {
  const successBody = JSON.parse(success.body);
  assert(success.status === 200, "Creative API should return success for safe requests.");
  assert(successBody.status === "completed", "Creative API should return a completed response.");
  assert(successBody.result.headline === "Server-Safe Creative Brief", "Creative API should return provider guidance.");
  assert(successBody.privacy.keepsOpenAIKeyOnServer === true, "Creative API should keep the OpenAI key on the server.");
  assert(successBody.privacy.acceptsClientOpenAIKey === false, "Creative API should reject OpenAI keys from clients.");
  assert(!success.body.includes("sk-test-server-side"), "Creative API response must not leak the server key.");

  assert(fetchCalls.length === 1, "Creative API should call OpenAI once for a safe request.");
  assert(fetchCalls[0].url === "https://api.openai.com/v1/responses", "Creative API should call the Responses endpoint.");
  assert(
    fetchCalls[0].options.headers.Authorization === "Bearer sk-test-server-side",
    "Creative API should apply the OpenAI key only server-side."
  );
  const openAIBody = JSON.parse(fetchCalls[0].options.body);
  assert(openAIBody.store === false, "Creative API should disable OpenAI response storage.");
  assert(openAIBody.text.format.type === "json_schema", "Creative API should request structured OpenAI output.");
  assert(openAIBody.tools[0].type === "web_search", "Creative API should allow public web search through the provider.");
  assert(!openAIBody.input.includes("private_photo"), "Creative API should not forward private-photo payload tokens.");

  const badMethod = await api.handle({
    method: "GET",
    headers: {},
    body: "{}",
  });
  assert(badMethod.status === 405, "Creative API should reject non-POST methods.");

  const badClientToken = await api.handle({
    method: "POST",
    headers: {
      authorization: "Bearer wrong-token",
    },
    body: JSON.stringify(safeApiRequest),
  });
  assert(badClientToken.status === 401, "Creative API should reject invalid client authorization when configured.");

  const clientOpenAIKeyApi = createLensPilotCreativeInterpretationApi({
    openAIAPIKey: "sk-test-server-side",
    fetchImpl: async () => {
      throw new Error("Client OpenAI key rejection should happen before provider fetch.");
    },
  });
  const clientKeyRejected = await clientOpenAIKeyApi.handle({
    method: "POST",
    headers: {
      authorization: "Bearer sk-proj-client-secret",
    },
    body: JSON.stringify(safeApiRequest),
  });
  assert(clientKeyRejected.status === 400, "Creative API should reject OpenAI keys sent by the client.");

  const missingServerKeyApi = createLensPilotCreativeInterpretationApi({
    openAIAPIKey: "",
    expectedClientToken: "client-token",
    fetchImpl: async () => {
      throw new Error("Missing server key should prevent provider fetch.");
    },
  });
  const missingServerKey = await missingServerKeyApi.handle({
    method: "POST",
    headers: {
      authorization: "Bearer client-token",
    },
    body: JSON.stringify(safeApiRequest),
  });
  assert(missingServerKey.status === 500, "Creative API should fail closed without a server OpenAI key.");

  const quotaBlockedApi = createLensPilotCreativeInterpretationApi({
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
  });
  const quotaBlocked = await quotaBlockedApi.handle({
    method: "POST",
    headers: {},
    body: JSON.stringify(safeApiRequest),
  });
  const quotaBlockedBody = JSON.parse(quotaBlocked.body);
  assert(quotaBlocked.status === 502, "Creative API should keep provider failures behind the backend boundary.");
  assert(quotaBlockedBody.error.code === "openai_credit_balance_exhausted", "Creative API should classify exhausted provider credits.");
  assert(quotaBlockedBody.error.providerStatus === 429, "Creative API should expose only the provider status code.");
  assert(quotaBlockedBody.error.providerErrorType === "insufficient_quota", "Creative API should expose sanitized provider error type.");
  assert(quotaBlockedBody.error.providerErrorCode === "credit_balance_exhausted", "Creative API should expose sanitized provider error code.");
  assert(quotaBlockedBody.error.blockedByBilling === true, "Creative API should mark billing-blocked provider failures.");
  assert(quotaBlockedBody.error.retryable === false, "Creative API should not mark exhausted credits as retryable.");
  assert(!quotaBlocked.body.includes("sk-test-server-side"), "Classified provider errors must not leak the server key.");

  const unsafeApiRequest = {
    ...safeApiRequest,
    request: {
      ...safeRequest,
      inputSummary: [...safeRequest.inputSummary, "raw_live_camera_feed should never be sent"],
    },
  };
  const unsafeRequest = await api.handle({
    method: "POST",
    headers: {
      authorization: "Bearer client-token",
    },
    body: JSON.stringify(unsafeApiRequest),
  });
  assert(unsafeRequest.status === 400, "Creative API should reject unsafe client summaries.");

  const invalidJSON = await api.handle({
    method: "POST",
    headers: {
      authorization: "Bearer client-token",
    },
    body: "{not-json",
  });
  assert(invalidJSON.status === 400, "Creative API should reject invalid JSON bodies.");

  const forgedAuditApiRequest = {
    ...safeApiRequest,
    request: {
      ...safeRequest,
      payloadAudit: {
        ...safePayloadAudit,
        blockedTermsDetected: ["raw_live_camera"],
      },
    },
  };
  const forgedAudit = await api.handle({
    method: "POST",
    headers: {
      authorization: "Bearer client-token",
    },
    body: JSON.stringify(forgedAuditApiRequest),
  });
  assert(forgedAudit.status === 400, "Creative API should reject forged unsafe payload audits.");

  const missingBlocklistApiRequest = {
    ...safeApiRequest,
    request: {
      ...safeRequest,
      mustNotSend: safeRequest.mustNotSend.filter((term) => term !== "private_photo"),
    },
  };
  const missingBlocklist = await api.handle({
    method: "POST",
    headers: {
      authorization: "Bearer client-token",
    },
    body: JSON.stringify(missingBlocklistApiRequest),
  });
  assert(missingBlocklist.status === 400, "Creative API should require the transmitted safety blocklist.");

  const tamperedHealthGateApiRequest = {
    ...safeApiRequest,
    healthGate: {
      ...safeHealthGate,
      publicReferenceCount: 0,
    },
  };
  const tamperedHealthGate = await api.handle({
    method: "POST",
    headers: {
      authorization: "Bearer client-token",
    },
    body: JSON.stringify(tamperedHealthGateApiRequest),
  });
  assert(tamperedHealthGate.status === 400, "Creative API should reject tampered provider health gates.");

  const forgedHealthGateAuditApiRequest = {
    ...safeApiRequest,
    healthGate: {
      ...safeHealthGate,
      payloadAudit: {
        ...safePayloadAudit,
        deniedReasons: ["unsafe_request_payload"],
      },
    },
  };
  const forgedHealthGateAudit = await api.handle({
    method: "POST",
    headers: {
      authorization: "Bearer client-token",
    },
    body: JSON.stringify(forgedHealthGateAuditApiRequest),
  });
  assert(forgedHealthGateAudit.status === 400, "Creative API should reject forged health-gate audits.");

  const nonTextSummaryApiRequest = {
    ...safeApiRequest,
    request: {
      ...safeRequest,
      inputSummary: [...safeRequest.inputSummary, { raw: "not text" }],
    },
  };
  const nonTextSummary = await api.handle({
    method: "POST",
    headers: {
      authorization: "Bearer client-token",
    },
    body: JSON.stringify(nonTextSummaryApiRequest),
  });
  assert(nonTextSummary.status === 400, "Creative API should only accept text summaries.");

  const unsafeProviderApi = createLensPilotCreativeInterpretationApi({
    openAIAPIKey: "sk-test-server-side",
    fetchImpl: async () => ({
      ok: true,
      status: 200,
      async json() {
        return {
          status: "completed",
          output_text: JSON.stringify({
            headline: "Unsafe Brief",
            guidance: ["Upload private_photo bytes before guidance."],
          }),
        };
      },
    }),
  });
  const unsafeProvider = await unsafeProviderApi.handle({
    method: "POST",
    headers: {},
    body: JSON.stringify(safeApiRequest),
  });
  assert(unsafeProvider.status === 502, "Creative API should reject unsafe provider output.");

  console.log(JSON.stringify({
    creativeApi: true,
    route: lensPilotCreativeInterpretationApiDefaults.path,
    serverSideOpenAIKey: true,
    rejectsClientOpenAIKey: true,
    status: "passed",
  }, null, 2));
}).catch((error) => {
  console.error(error);
  process.exit(1);
});

function assert(condition, message) {
  if (!condition) {
    console.error(message);
    process.exit(1);
  }
}
