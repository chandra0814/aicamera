export const lensPilotCreativeInterpretationApiDefaults = {
  apiVersion: "2026-08-31",
  path: "/v1/creative-interpretation",
  method: "POST",
  requiresServerSideOpenAIKey: true,
  acceptsClientOpenAIKey: false,
  openAIEndpoint: "https://api.openai.com/v1/responses",
  openAIModel: "gpt-5.6-luna",
  maxToolCalls: 2,
};

export const lensPilotCreativeInterpretationApiPrivacy = {
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

const requiredCreativeInterpretationMustNotSendTerms = [
  "raw_live_camera_feed",
  "private_photo",
  "face_identity",
  "precise_location_without_consent",
  "raw_learning_events",
];

const creativeInterpretationBlockedPayloadTerms = [
  "raw_live_camera",
  "private_photo",
  "face_identity",
  "identity_recognition",
  "precise_location",
  "gps",
  "latitude",
  "longitude",
  "exif",
  "raw_learning_event",
  "base64",
  "image_data",
  "photo_bytes",
];

const unsafeCreativeInterpretationProviderOutputTerms = [
  "raw_live_camera",
  "raw camera frame",
  "private_photo",
  "private photo",
  "face_identity",
  "face identity",
  "identity_recognition",
  "identity recognition",
  "precise_location",
  "precise location",
  "gps",
  "latitude",
  "longitude",
  "exif",
  "raw_learning_event",
  "raw learning event",
  "base64",
  "image_data",
  "photo_bytes",
  "generate an image",
  "generative edit",
  "sky replacement",
  "object removal",
];

const openAICreativeInterpretationInstructions =
  "You are LensPilot AI's photography reasoning provider. Return only JSON matching the schema. Use only the audited text summary and public-reference context in the request. Do not ask for or mention uploading live camera frames, private photos, identity data, precise location, raw learning events, EXIF, base64, or photo bytes. Keep guidance capture-realistic, concise, and useful for one phone in the user's hand. Do not promise generated edits, object removal, sky replacement, or a synthetic final image.";

const openAICreativeInterpretationResponseFormat = {
  type: "json_schema",
  name: "lenspilot_creative_interpretation",
  strict: true,
  schema: {
    type: "object",
    additionalProperties: false,
    properties: {
      headline: {
        type: "string",
        maxLength: 96,
      },
      guidance: {
        type: "array",
        minItems: 2,
        maxItems: 4,
        items: {
          type: "string",
          maxLength: 180,
        },
      },
    },
    required: ["headline", "guidance"],
  },
};

export function createLensPilotCreativeInterpretationApi(options = {}) {
  const environment = options.environment ?? globalThis.process?.env ?? {};
  const config = {
    openAIAPIKey: cleanOptional(options.openAIAPIKey ?? environment.OPENAI_API_KEY),
    expectedClientToken: cleanOptional(options.expectedClientToken ?? environment.LENSPILOT_CREATIVE_API_TOKEN),
    openAIEndpoint: cleanOptional(options.openAIEndpoint) ?? lensPilotCreativeInterpretationApiDefaults.openAIEndpoint,
    model: cleanOptional(options.model ?? environment.LENSPILOT_OPENAI_MODEL) ?? lensPilotCreativeInterpretationApiDefaults.openAIModel,
    allowsWebSearch: parseBooleanOption(options.allowsWebSearch ?? environment.LENSPILOT_OPENAI_WEB_SEARCH, true),
    fetchImpl: options.fetchImpl ?? globalThis.fetch,
    now: options.now ?? (() => new Date().toISOString()),
  };

  return {
    async handle(requestLike) {
      return handleCreativeInterpretationRequest(requestLike, config);
    },
  };
}

export function createLensPilotCreativeInterpretationFetchHandler(options = {}) {
  const api = createLensPilotCreativeInterpretationApi(options);
  return async function handleFetchRequest(request) {
    const result = await api.handle(request);
    return new Response(result.body, {
      status: result.status,
      headers: result.headers,
    });
  };
}

export function makeOpenAICreativeInterpretationResponsesPayload(request, options = {}) {
  if (!isCreativeInterpretationRequestSafe(request)) {
    throw new Error("unsafe_openai_creative_interpretation_request");
  }

  const payload = {
    model: cleanOptional(options.model) ?? lensPilotCreativeInterpretationApiDefaults.openAIModel,
    instructions: openAICreativeInterpretationInstructions,
    input: openAICreativeInterpretationInputText(request),
    store: false,
    max_output_tokens: Math.min(640, Math.max(96, request.maxResponseWords * 3)),
    reasoning: {
      effort: "low",
    },
    text: {
      format: openAICreativeInterpretationResponseFormat,
    },
    metadata: {
      lenspilot_plan_id: String(request.planId).slice(0, 64),
      lenspilot_provider: request.provider,
      lenspilot_payload: "audited_text_only",
    },
  };

  if (options.allowsWebSearch ?? true) {
    payload.tools = [{ type: "web_search" }];
    payload.tool_choice = "auto";
    payload.max_tool_calls = Math.min(
      4,
      Math.max(1, Math.trunc(options.maxToolCalls ?? lensPilotCreativeInterpretationApiDefaults.maxToolCalls))
    );
  }

  return payload;
}

export function parseOpenAICreativeInterpretationProviderResult(payload) {
  if (!isRecord(payload)) {
    throw new Error("invalid_openai_creative_interpretation_response");
  }

  if (isRecord(payload.error)) {
    throw new Error("openai_creative_interpretation_api_error");
  }

  if (typeof payload.status === "string" && payload.status !== "completed") {
    throw new Error(`openai_creative_interpretation_incomplete:${payload.status}`);
  }

  const outputText = typeof payload.output_text === "string"
    ? payload.output_text
    : firstOpenAIOutputText(payload.output);
  if (!outputText) {
    throw new Error("missing_openai_creative_interpretation_output_text");
  }

  let parsed;
  try {
    parsed = JSON.parse(outputText);
  } catch {
    throw new Error("invalid_openai_creative_interpretation_json");
  }

  if (!isRecord(parsed) || typeof parsed.headline !== "string" || !Array.isArray(parsed.guidance)) {
    throw new Error("invalid_openai_creative_interpretation_json");
  }

  const result = makeCreativeInterpretationProviderResult(
    parsed.headline,
    parsed.guidance.filter((item) => typeof item === "string")
  );
  if (!isCreativeInterpretationProviderResultSafe(result)) {
    throw new Error("unsafe_creative_interpretation_provider_output");
  }

  return result;
}

export function makeLensPilotCreativeInterpretationApiResponse(apiRequest, result, generatedAt) {
  if (!isLensPilotCreativeInterpretationApiRequestSafe(apiRequest)) {
    throw new Error("unsafe_lenspilot_creative_interpretation_api_request");
  }
  if (!isCreativeInterpretationProviderResultSafe(result) || result.guidance.length === 0) {
    throw new Error("unsafe_lenspilot_creative_interpretation_api_response");
  }

  return {
    apiVersion: lensPilotCreativeInterpretationApiDefaults.apiVersion,
    status: "completed",
    provider: apiRequest.request.provider,
    result,
    generatedAt,
    privacy: lensPilotCreativeInterpretationApiPrivacy,
  };
}

export function isLensPilotCreativeInterpretationApiRequestSafe(apiRequest) {
  return isRecord(apiRequest) &&
    apiRequest.apiVersion === lensPilotCreativeInterpretationApiDefaults.apiVersion &&
    isRecord(apiRequest.client) &&
    apiRequest.client.platform === "ios" &&
    isCreativeInterpretationRequestSafe(apiRequest.request) &&
    isCreativeInterpretationProviderHealthGateSafe(apiRequest.healthGate) &&
    !containsClientOpenAIKey(apiRequest);
}

async function handleCreativeInterpretationRequest(requestLike, config) {
  const method = String(requestLike?.method ?? "GET").toUpperCase();
  if (method !== lensPilotCreativeInterpretationApiDefaults.method) {
    return jsonResponse(405, {
      error: {
        code: "method_not_allowed",
        message: "Use POST for creative interpretation.",
      },
    });
  }

  const headers = normalizeHeaders(requestLike?.headers);
  if (containsClientOpenAIKey(headers)) {
    return jsonResponse(400, {
      error: {
        code: "client_openai_key_rejected",
        message: "OpenAI keys must stay on the server.",
      },
    });
  }

  if (config.expectedClientToken) {
    const expectedAuthorization = `Bearer ${config.expectedClientToken}`;
    if (headerValue(headers, "authorization") !== expectedAuthorization) {
      return jsonResponse(401, {
        error: {
          code: "unauthorized",
          message: "Creative API client authorization failed.",
        },
      });
    }
  }

  let body;
  try {
    body = await parseJSONBody(requestLike);
  } catch {
    return jsonResponse(400, {
      error: {
        code: "invalid_json_body",
        message: "Creative API request body must be valid JSON.",
      },
    });
  }

  if (!isRecord(body) || containsClientOpenAIKey(body)) {
    return jsonResponse(400, {
      error: {
        code: "unsafe_request",
        message: "Creative API request body is unsafe.",
      },
    });
  }

  const apiRequest = {
    apiVersion: body.apiVersion,
    request: body.request,
    healthGate: body.healthGate,
    client: body.client,
  };
  if (!isLensPilotCreativeInterpretationApiRequestSafe(apiRequest)) {
    return jsonResponse(400, {
      error: {
        code: "unsafe_request",
        message: "Creative API request failed the single-phone safety gate.",
      },
    });
  }

  if (!config.openAIAPIKey) {
    return jsonResponse(500, {
      error: {
        code: "missing_server_openai_key",
        message: "Creative API is not configured.",
      },
    });
  }

  if (typeof config.fetchImpl !== "function") {
    return jsonResponse(500, {
      error: {
        code: "fetch_unavailable",
        message: "Creative API fetch runtime is unavailable.",
      },
    });
  }

  const openAIPayload = makeOpenAICreativeInterpretationResponsesPayload(apiRequest.request, {
    model: config.model,
    allowsWebSearch: config.allowsWebSearch,
    maxToolCalls: lensPilotCreativeInterpretationApiDefaults.maxToolCalls,
  });

  let openAIResponse;
  try {
    openAIResponse = await config.fetchImpl(config.openAIEndpoint, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${config.openAIAPIKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(openAIPayload),
    });
  } catch {
    return jsonResponse(502, {
      error: {
        code: "openai_request_failed",
        message: "Creative provider request failed.",
      },
    });
  }

  if (!openAIResponse?.ok) {
    return jsonResponse(502, {
      error: {
        code: "openai_request_failed",
        message: "Creative provider returned an unsuccessful status.",
      },
    });
  }

  let openAIJSON;
  try {
    openAIJSON = await readJSONResponse(openAIResponse);
  } catch {
    return jsonResponse(502, {
      error: {
        code: "openai_invalid_json",
        message: "Creative provider response could not be read.",
      },
    });
  }

  let result;
  try {
    result = parseOpenAICreativeInterpretationProviderResult(openAIJSON);
  } catch {
    return jsonResponse(502, {
      error: {
        code: "unsafe_provider_response",
        message: "Creative provider response failed safety validation.",
      },
    });
  }

  return jsonResponse(200, makeLensPilotCreativeInterpretationApiResponse(apiRequest, result, config.now()));
}

function isCreativeInterpretationRequestSafe(request) {
  return isRecord(request) &&
    request.provider === "online_reasoning" &&
    isRecord(request.payloadAudit) &&
    request.payloadAudit.safeToSend === true &&
    Array.isArray(request.payloadAudit.deniedReasons) &&
    request.payloadAudit.deniedReasons.length === 0 &&
    Array.isArray(request.payloadAudit.blockedTermsDetected) &&
    request.payloadAudit.blockedTermsDetected.length === 0 &&
    isNonEmptyStringArray(request.allowedInputs) &&
    isNonEmptyStringArray(request.mustNotSend) &&
    isNonEmptyStringArray(request.inputSummary) &&
    isNonEmptyStringArray(request.suggestionBriefs) &&
    Number.isFinite(request.maxResponseWords) &&
    request.maxResponseWords >= 40 &&
    request.maxResponseWords <= 240 &&
    isCreativeInterpretationPrivacySafe(request.privacy) &&
    requiredCreativeInterpretationMustNotSendTerms.every((term) => request.mustNotSend.includes(term)) &&
    detectedCreativeInterpretationBlockedPayloadTerms(request).length === 0;
}

function isCreativeInterpretationPrivacySafe(privacy) {
  return isRecord(privacy) &&
    privacy.singlePhoneOnly === true &&
    privacy.requiresUserConsent === true &&
    privacy.sendsRawCameraFrame === false &&
    privacy.sendsPrivatePhoto === false &&
    privacy.sendsIdentityData === false &&
    privacy.sendsPreciseLocation === false &&
    privacy.sendsRawLearningEvents === false &&
    privacy.allowsGenerativeOutput === false;
}

function isCreativeInterpretationProviderHealthGateSafe(healthGate) {
  return isRecord(healthGate) &&
    healthGate.canRunProvider === true &&
    (healthGate.providerHealthStatus === "available" || healthGate.providerHealthStatus === "degraded") &&
    Number.isFinite(healthGate.publicReferenceCount) &&
    healthGate.publicReferenceCount > 0 &&
    isRecord(healthGate.payloadAudit) &&
    healthGate.payloadAudit.safeToSend === true &&
    Array.isArray(healthGate.payloadAudit.deniedReasons) &&
    healthGate.payloadAudit.deniedReasons.length === 0 &&
    Array.isArray(healthGate.payloadAudit.blockedTermsDetected) &&
    healthGate.payloadAudit.blockedTermsDetected.length === 0 &&
    isRecord(healthGate.privacy) &&
    healthGate.privacy.singlePhoneOnly === true &&
    healthGate.privacy.requiresUserConsent === true &&
    healthGate.privacy.sendsRawCameraFrame === false &&
    healthGate.privacy.sendsPrivatePhoto === false &&
    healthGate.privacy.sendsIdentityData === false &&
    healthGate.privacy.sendsPreciseLocation === false &&
    healthGate.privacy.sendsRawLearningEvents === false;
}

function detectedCreativeInterpretationBlockedPayloadTerms(request) {
  const inspectedText = [
    ...(Array.isArray(request.inputSummary) ? request.inputSummary : []),
    ...(Array.isArray(request.suggestionBriefs) ? request.suggestionBriefs : []),
  ].join(" ").toLowerCase();
  return creativeInterpretationBlockedPayloadTerms.filter((term) => inspectedText.includes(term));
}

function openAICreativeInterpretationInputText(request) {
  const summary = request.inputSummary
    .slice(0, 8)
    .map((item) => `- ${item}`)
    .join("\n");
  const suggestions = request.suggestionBriefs
    .slice(0, 6)
    .map((item) => `- ${item}`)
    .join("\n");

  return [
    "LensPilot creative interpretation request.",
    `Plan id: ${request.planId}`,
    `Allowed input classes: ${request.allowedInputs.join(", ")}`,
    `Max response words: ${request.maxResponseWords}`,
    "",
    "Safe input summary:",
    summary,
    "",
    "Candidate capture guidance:",
    suggestions,
    "",
    "Return a short headline and 2-4 capture-realistic guidance strings.",
  ].join("\n");
}

function makeCreativeInterpretationProviderResult(headline, guidance) {
  return {
    headline: cleanProviderText(headline, 96),
    guidance: guidance
      .map((item) => cleanProviderText(item, 180))
      .filter(Boolean)
      .slice(0, 4),
  };
}

function isCreativeInterpretationProviderResultSafe(result) {
  const inspectedText = [result.headline, ...result.guidance].join(" ").toLowerCase();
  return !unsafeCreativeInterpretationProviderOutputTerms.some((term) => inspectedText.includes(term));
}

function firstOpenAIOutputText(output) {
  if (!Array.isArray(output)) return undefined;

  for (const item of output) {
    if (!isRecord(item) || !Array.isArray(item.content)) continue;

    for (const content of item.content) {
      if (isRecord(content) && content.type === "output_text" && typeof content.text === "string") {
        return content.text;
      }
    }
  }

  return undefined;
}

async function parseJSONBody(requestLike) {
  if (typeof requestLike?.json === "function") {
    return requestLike.json();
  }

  const body = requestLike?.body;
  if (typeof body === "string") {
    return JSON.parse(body);
  }
  if (body instanceof Uint8Array) {
    return JSON.parse(new TextDecoder().decode(body));
  }
  if (isRecord(body)) {
    return body;
  }

  throw new Error("invalid_json_body");
}

async function readJSONResponse(response) {
  if (typeof response.json === "function") {
    return response.json();
  }
  if (typeof response.text === "function") {
    return JSON.parse(await response.text());
  }
  if (typeof response.body === "string") {
    return JSON.parse(response.body);
  }
  if (isRecord(response.body)) {
    return response.body;
  }

  throw new Error("invalid_json_response");
}

function normalizeHeaders(headers) {
  if (!headers) return {};
  if (typeof headers.get === "function") {
    const normalized = {};
    for (const key of ["authorization", "content-type", "x-lenspilot-client"]) {
      const value = headers.get(key);
      if (value) normalized[key] = value;
    }
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

function containsClientOpenAIKey(value) {
  if (typeof value === "string") {
    const normalized = value.toLowerCase();
    return normalized.includes("openai_api_key") || /(^|[\s"'=:])sk-(proj-)?[a-z0-9_-]{8,}/i.test(value);
  }

  if (Array.isArray(value)) {
    return value.some(containsClientOpenAIKey);
  }

  if (isRecord(value)) {
    return Object.entries(value).some(([key, nestedValue]) => {
      const normalizedKey = key.toLowerCase();
      return normalizedKey === "openai_api_key" ||
        normalizedKey === "apikey" ||
        normalizedKey === "api_key" ||
        containsClientOpenAIKey(nestedValue);
    });
  }

  return false;
}

function parseBooleanOption(value, fallback) {
  const cleaned = cleanOptional(value);
  if (!cleaned) return fallback;
  return !["0", "false", "no", "off"].includes(cleaned.toLowerCase());
}

function cleanOptional(value) {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function cleanProviderText(value, maxLength) {
  const collapsed = value
    .split(/\s+/)
    .join(" ")
    .trim();
  return collapsed.length <= maxLength ? collapsed : collapsed.slice(0, maxLength).trim();
}

function jsonResponse(status, payload) {
  return {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
    body: JSON.stringify(payload),
  };
}

function isRecord(value) {
  return typeof value === "object" && value !== null;
}

function isNonEmptyStringArray(value) {
  return Array.isArray(value) &&
    value.length > 0 &&
    value.every((item) => typeof item === "string" && item.trim().length > 0);
}
