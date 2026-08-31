const disabledConsent = {
  learningEnabled: false,
  onlineReferencesAllowed: false,
  cloudPersonalizationSyncAllowed: false,
};

const localLearningConsent = {
  learningEnabled: true,
  onlineReferencesAllowed: false,
  cloudPersonalizationSyncAllowed: false,
};

const onlineReferenceConsent = {
  learningEnabled: true,
  onlineReferencesAllowed: true,
  cloudPersonalizationSyncAllowed: false,
};

const personalVisualProfileStoragePolicy = {
  storageKey: "com.lenspilot.personalVisualProfile.v1",
  preferredProtection: "keychain_encrypted_this_device_only",
  legacyProtection: "local_file",
  maxStoredProfileBytes: 64 * 1024,
  privacy: {
    localOnly: true,
    encryptedAtRestPreferred: true,
    migratesLegacyUserDefaults: true,
    storesRawPhoto: false,
    uploadsLiveCameraFrame: false,
    storesIdentityData: false,
    cloudPersonalizationSyncAllowed: false,
  },
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

const openAICreativeInterpretationDefaults = {
  endpoint: "https://api.openai.com/v1/responses",
  model: "gpt-5.6-luna",
  store: false,
  maxToolCalls: 2,
  privacy: {
    sendsRawCameraFrame: false,
    sendsPrivatePhoto: false,
    sendsIdentityData: false,
    sendsPreciseLocation: false,
    sendsRawLearningEvents: false,
    allowsGenerativeImageOutput: false,
  },
};

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

const shotSpec = {
  id: "shot_personalization_fixture",
  domain: "portrait",
  subject: { primary: "person" },
  style: { name: "cinematic", mood: "dramatic", colorIntent: "warm_highlights_cool_shadows" },
  composition: { framing: "environmental", skyPriority: "high", backgroundPriority: "clean" },
};

const event = {
  id: "learn_event_001",
  timestamp: "2026-08-17T00:00:00.000Z",
  domain: "portrait",
  outcome: "saved_result",
  promptRequirements: ["cinematic", "clean_background", "natural_skin"],
  acceptedGuidanceReason: "reduce_clutter",
  selectedStyle: "cinematic",
  selectedColorIntent: "warm_highlights_cool_shadows",
  selectedFraming: "environmental",
  selectedTargetMatch: 0.91,
  userRating: 5,
  onlineReferenceUsed: true,
  privacy: {
    singlePhoneOnly: true,
    storesRawPhoto: false,
    uploadsLiveCameraFrame: false,
    identityRecognitionAllowed: false,
  },
};

let profile = emptyProfile(disabledConsent);
profile = updatedProfile(profile, event, disabledConsent);
assert(profile.totalEvents === 0, "Disabled learning must not collect events.");

profile = updatedProfile(emptyProfile(localLearningConsent), event, localLearningConsent);
assert(profile.totalEvents === 1, "Local learning should record safe structured events.");
assert(profile.domainCounts.portrait === 1, "Domain counts should learn usage context.");
assert((profile.styleAffinities.cinematic ?? 0) > 0, "Style affinity should learn from selected results.");
assert((profile.guidanceReasonAffinities.reduce_clutter ?? 0) > 0, "Accepted guidance should increase reason affinity.");
assert(profile.onlineReferenceUsageCount === 1, "Online reference usage should be counted without storing a photo.");

const calibration = guidanceCalibration(profile);
assert((calibration.globalReasonBoosts.reduce_clutter ?? 0) > 0, "Positive guidance affinity should become a small boost.");
assert((calibration.globalReasonBoosts.reduce_clutter ?? 0) <= 0.04, "Personal boosts must stay secondary.");

let insightProfile = emptyProfile(localLearningConsent);
for (let index = 0; index < 3; index += 1) {
  insightProfile = updatedProfile(insightProfile, {
    ...event,
    id: `learning_insight_${index}`,
    onlineReferenceUsed: index === 0,
  }, localLearningConsent);
}
const learningInsight = makePersonalVisualLearningInsight(insightProfile, 8);
const disabledLearningInsight = makePersonalVisualLearningInsight(emptyProfile(disabledConsent));
assert(disabledLearningInsight.status === "disabled", "Learning insight should report disabled consent.");
assert(learningInsight.status === "personalized", "Learning insight should become personalized after enough local events.");
assert(learningInsight.eventCount === 3, "Learning insight should expose the aggregate local event count.");
assert(learningInsight.topSignals.some((signal) => signal.category === "style" && signal.label === "Cinematic"), "Learning insight should show learned style preference.");
assert(learningInsight.topSignals.some((signal) => signal.category === "guidance" && signal.label === "Reduce Clutter"), "Learning insight should show learned guidance preference.");
assert(learningInsight.topSignals.some((signal) => signal.category === "requirement"), "Learning insight should include learned prompt requirements.");
assert((learningInsight.guidanceBoosts.reduce_clutter ?? 0) > 0, "Learning insight should expose the small personal guidance boost.");
assert(learningInsight.privacy.singlePhoneOnly === true, "Learning insight should remain single-phone.");
assert(learningInsight.privacy.storesRawPhoto === false, "Learning insight must not store raw photos.");
assert(learningInsight.privacy.uploadsLiveCameraFrame === false, "Learning insight must not upload live frames.");
assert(learningInsight.privacy.storesIdentityData === false, "Learning insight must not store identity data.");
assert(learningInsight.privacy.cloudPersonalizationSyncAllowed === false, "Learning insight must not enable cloud personalization sync.");

const rejectedProfile = updatedProfile(emptyProfile(localLearningConsent), {
  ...event,
  id: "learn_rejected_result",
  outcome: "rejected_guidance",
  rejectedGuidanceReason: "reduce_clutter",
  acceptedGuidanceReason: undefined,
  customerCorrectionReason: undefined,
  selectedTargetMatch: 0.42,
  userRating: 1,
  onlineReferenceUsed: false,
}, localLearningConsent);
assert(rejectedProfile.totalEvents === 1, "Rejected feedback should still count as a local structured event.");
assert((rejectedProfile.styleAffinities.cinematic ?? 0) < 0, "Rejected results should reduce style affinity.");
assert((rejectedProfile.requirementAffinities.clean_background ?? 0) < 0, "Rejected results should reduce requirement affinity.");
assert((rejectedProfile.guidanceReasonAffinities.reduce_clutter ?? 0) < 0, "Rejected guidance should reduce reason affinity.");
assert(!guidanceCalibration(rejectedProfile).globalReasonBoosts.reduce_clutter, "Negative feedback should not become a positive guidance boost.");

const correctionProfile = updatedProfile(emptyProfile(localLearningConsent), {
  ...event,
  id: "learn_customer_correction_reason",
  outcome: "rejected_guidance",
  acceptedGuidanceReason: undefined,
  rejectedGuidanceReason: undefined,
  customerCorrectionReason: "improve_face_light",
  selectedTargetMatch: 0.36,
  userRating: 1,
  onlineReferenceUsed: false,
}, localLearningConsent);
assert(correctionProfile.totalEvents === 1, "Customer correction feedback should count as a local structured event.");
assert((correctionProfile.styleAffinities.cinematic ?? 0) < 0, "A rejected result should still reduce the current style signal.");
assert((correctionProfile.guidanceReasonAffinities.improve_face_light ?? 0) > 0, "Customer correction should increase the selected future guidance reason.");
assert((correctionProfile.requirementAffinities.customer_correction_improve_face_light ?? 0) > 0, "Customer correction should store a safe aggregate requirement signal.");
assert((guidanceCalibration(correctionProfile).globalReasonBoosts.improve_face_light ?? 0) > 0, "Customer correction should become a small personal guidance boost.");
assert((guidanceCalibration(correctionProfile).globalReasonBoosts.improve_face_light ?? 0) <= 0.04, "Customer correction boost must stay secondary.");

const unsafeStoredProfile = {
  ...profile,
  version: "legacy",
  consent: { ...onlineReferenceConsent, cloudPersonalizationSyncAllowed: true },
  totalEvents: 2_000_000,
  domainCounts: { ...profile.domainCounts, external_cloud_album: 7, night: -2 },
  styleAffinities: { ...profile.styleAffinities, unknown_cloud_style: 0.9 },
  colorAffinities: { ...profile.colorAffinities, generated_identity_palette: 0.7 },
  guidanceReasonAffinities: { ...profile.guidanceReasonAffinities, upload_private_photo: 1 },
  requirementAffinities: { ...profile.requirementAffinities, "Clean Background!!": 0.6 },
};
const storageSnapshot = makePersonalVisualProfileStorageSnapshot(unsafeStoredProfile);
assert(storageSnapshot.storageKey === personalVisualProfileStoragePolicy.storageKey, "Profile storage key should be stable.");
assert(storageSnapshot.storageProtection === "keychain_encrypted_this_device_only", "Profile storage should prefer Keychain encryption.");
assert(storageSnapshot.privacy.localOnly === true, "Profile storage must stay local-only.");
assert(storageSnapshot.privacy.encryptedAtRestPreferred === true, "Profile storage should prefer encryption at rest.");
assert(storageSnapshot.privacy.migratesLegacyUserDefaults === true, "Profile storage should migrate the legacy local store.");
assert(storageSnapshot.privacy.storesRawPhoto === false, "Profile storage must not store raw photos.");
assert(storageSnapshot.privacy.uploadsLiveCameraFrame === false, "Profile storage must not upload live frames.");
assert(storageSnapshot.privacy.storesIdentityData === false, "Profile storage must not store identity data.");
assert(storageSnapshot.profile.version === "1.0", "Stored profile should use the current schema version.");
assert(storageSnapshot.profile.consent.cloudPersonalizationSyncAllowed === false, "Stored profile must strip cloud sync.");
assert(storageSnapshot.profile.totalEvents === 1_000_000, "Stored profile event counts should be capped.");
assert(!storageSnapshot.profile.domainCounts.external_cloud_album, "Stored profile should drop unknown domains.");
assert(!storageSnapshot.profile.styleAffinities.unknown_cloud_style, "Stored profile should drop unknown styles.");
assert(!storageSnapshot.profile.guidanceReasonAffinities.upload_private_photo, "Stored profile should drop unsafe guidance reasons.");
assert(storageSnapshot.profile.requirementAffinities.clean_background > 0, "Stored profile should sanitize learned requirement keys.");
assert(!storageSnapshot.profile.requirementAffinities.raw_live_camera_feed, "Stored profile should drop reserved raw-frame requirement keys.");
const encodedProfile = encodePersonalVisualPreferenceProfileForLocalStorage(unsafeStoredProfile);
const decodedProfile = decodePersonalVisualPreferenceProfileFromLocalStorage(encodedProfile);
assert(decodedProfile.consent.cloudPersonalizationSyncAllowed === false, "Decoded profile should remain local-only.");
assertThrows(
  () => decodePersonalVisualPreferenceProfileFromLocalStorage("x".repeat(personalVisualProfileStoragePolicy.maxStoredProfileBytes + 1)),
  "Oversized stored profiles should be rejected."
);

const blockedPlan = makeOnlineReferencePlan(shotSpec, "Give me a cinematic portrait", profile, localLearningConsent);
assert(blockedPlan === undefined, "Online references require explicit online consent.");

const plan = makeOnlineReferencePlan(
  shotSpec,
  "Give me a cinematic portrait with online inspiration",
  profile,
  onlineReferenceConsent
);
assert(plan, "Online reference plan should be created after consent.");
assert(plan.privacy.singlePhoneOnly === true, "Online inspiration must remain single-phone.");
assert(plan.privacy.sendsRawCameraFrame === false, "Online inspiration must not upload raw live camera frames.");
assert(plan.privacy.sendsPrivatePhoto === false, "Online inspiration must not upload private photos.");
assert(plan.privacy.sendsIdentityData === false, "Online inspiration must not send identity data.");
assert(plan.allowedInputs.includes("prompt_text"), "Online inspiration may use prompt text.");
assert(plan.mustNotSend.includes("raw_live_camera_feed"), "Online inspiration must block live camera upload.");
assert(plan.searchQueries.some((query) => query.includes("cinematic")), "Online inspiration should preserve the requested style.");

const blockedCreativePlan = makeCreativeInterpretationPlan(
  shotSpec,
  "Give me a cinematic portrait with online inspiration",
  profile,
  undefined,
  localLearningConsent
);
assert(blockedCreativePlan === undefined, "Creative interpretation requires online/reference consent.");

const creativePlan = makeCreativeInterpretationPlan(
  shotSpec,
  "Give me a cinematic portrait with online inspiration",
  insightProfile,
  plan,
  onlineReferenceConsent
);
assert(creativePlan, "Creative interpretation should be created for consented creative prompts.");
assert(creativePlan.reason === "explicit_user_request", "Creative interpretation should preserve explicit user intent.");
assert(creativePlan.allowedInputs.includes("learned_preference_summary"), "Creative interpretation may use aggregate learned preference summaries.");
assert(creativePlan.allowedInputs.includes("public_reference_summary"), "Creative interpretation may use public-reference summaries.");
assert(creativePlan.suggestions.some((suggestion) => suggestion.category === "reference"), "Creative interpretation should include reference guidance.");
assert(creativePlan.suggestions.some((suggestion) => suggestion.category === "lighting"), "Creative interpretation should include lighting guidance.");
assert(creativePlan.privacy.singlePhoneOnly === true, "Creative interpretation must stay single-phone.");
assert(creativePlan.privacy.sendsRawCameraFrame === false, "Creative interpretation must not upload live frames.");
assert(creativePlan.privacy.sendsPrivatePhoto === false, "Creative interpretation must not upload private photos.");
assert(creativePlan.privacy.sendsIdentityData === false, "Creative interpretation must not send identity data.");
assert(creativePlan.privacy.sendsPreciseLocation === false, "Creative interpretation must not send precise location.");
assert(creativePlan.privacy.sendsRawLearningEvents === false, "Creative interpretation must not send raw learning events.");
assert(creativePlan.privacy.allowsGenerativeOutput === false, "Creative interpretation must not imply generated output.");
assert(creativePlan.mustNotSend.includes("raw_learning_events"), "Creative interpretation should block raw learning events.");
assert(creativePlan.inputSummary.every((item) => !item.includes("raw_live_camera")), "Creative interpretation summaries must be sanitized.");

const creativePayloadAudit = makeCreativeInterpretationPayloadAudit(creativePlan);
assert(creativePayloadAudit.safeToSend === true, "Creative interpretation payload audit should pass safe plans.");
assert(creativePayloadAudit.deniedReasons.length === 0, "Safe creative payload audit should have no denied reasons.");
assert(creativePayloadAudit.allowedInputCount === creativePlan.allowedInputs.length, "Creative payload audit should count allowed inputs.");
assert(creativePayloadAudit.suggestionCount === creativePlan.suggestions.length, "Creative payload audit should count suggestions.");

const creativeRequest = makeCreativeInterpretationRequest(creativePlan, "online_reasoning", 999);
assert(creativeRequest.planId === creativePlan.id, "Creative interpretation request should target the selected plan.");
assert(creativeRequest.provider === "online_reasoning", "Creative interpretation request should support online reasoning providers.");
assert(creativeRequest.maxResponseWords === 240, "Creative interpretation request response length should be clamped.");
assert(creativeRequest.payloadAudit.safeToSend === true, "Creative interpretation request should include a passing payload audit.");
assert(creativeRequest.suggestionBriefs.some((brief) => brief.includes("Stay Capture-Realistic")), "Creative interpretation request should preserve safety guidance.");
assert(creativeRequest.privacy.sendsPrivatePhoto === false, "Creative interpretation request must not send private photos.");

const unsafeCreativePayloadPlan = {
  ...creativePlan,
  inputSummary: [...creativePlan.inputSummary, "Prompt: raw_live_camera_feed base64 image_data"],
  mustNotSend: ["private_photo"],
};
const unsafeCreativePayloadAudit = makeCreativeInterpretationPayloadAudit(unsafeCreativePayloadPlan);
assert(unsafeCreativePayloadAudit.safeToSend === false, "Creative payload audit should fail unsafe summaries.");
assert(unsafeCreativePayloadAudit.blockedTermsDetected.includes("raw_live_camera"), "Creative payload audit should detect raw camera terms.");
assert(unsafeCreativePayloadAudit.deniedReasons.includes("blocked_term_detected"), "Creative payload audit should report blocked terms.");
assert(unsafeCreativePayloadAudit.deniedReasons.includes("missing_required_blocklist"), "Creative payload audit should require the full blocklist.");
assertThrows(
  () => makeCreativeInterpretationRequest(unsafeCreativePayloadPlan),
  "Unsafe creative interpretation requests should be rejected before provider calls."
);

const inspirationRequest = makeOnlineInspirationRequest(plan, 50);
assert(inspirationRequest.perQueryLimit === 10, "Online provider limit should be clamped.");
assert(inspirationRequest.source === "public_sources", "Online inspiration should request diverse public sources by default.");
assert(inspirationRequest.privacy.sendsRawCameraFrame === false, "Online provider request must not include camera frames.");

const commonsUrl = new URL(buildWikimediaCommonsSearchUrl("cinematic portrait phone photography reference", 50));
assert(commonsUrl.hostname === "commons.wikimedia.org", "Wikimedia provider should use Commons.");
assert(commonsUrl.searchParams.get("generator") === "search", "Wikimedia provider should use search generator.");
assert(commonsUrl.searchParams.get("gsrnamespace") === "6", "Wikimedia provider should restrict search to files.");
assert(commonsUrl.searchParams.get("gsrlimit") === "10", "Wikimedia search limit should be clamped.");
assert(commonsUrl.searchParams.get("iiprop").includes("url"), "Wikimedia search should request image URLs.");

const openverseUrl = new URL(buildOpenverseSearchUrl("cinematic portrait phone photography reference", 50));
assert(openverseUrl.hostname === "api.openverse.engineering", "Openverse provider should use the public API host.");
assert(openverseUrl.searchParams.get("q") === "cinematic portrait phone photography reference", "Openverse provider should pass prompt-derived query text.");
assert(openverseUrl.searchParams.get("page_size") === "10", "Openverse search limit should be clamped.");
assert(openverseUrl.searchParams.get("mature") === "false", "Openverse provider should request non-mature public references.");

const publicReferenceResults = parseWikimediaCommonsSearchResponse({
  query: {
    pages: [
      {
        pageid: 42,
        index: 1,
        title: "File:Cinematic portrait reference.jpg",
        imageinfo: [{
          url: "https://upload.wikimedia.org/wikipedia/commons/example.jpg",
          thumburl: "https://upload.wikimedia.org/wikipedia/commons/thumb/example.jpg/640px-example.jpg",
          descriptionurl: "https://commons.wikimedia.org/wiki/File:Cinematic_portrait_reference.jpg",
          mime: "image/jpeg",
          extmetadata: {
            LicenseShortName: { value: "CC BY-SA 4.0" },
            Artist: { value: "<span>Jane Doe</span>" },
          },
        }],
      },
      {
        pageid: 43,
        index: 2,
        title: "File:Skipped document.pdf",
        imageinfo: [{
          url: "https://upload.wikimedia.org/wikipedia/commons/example.pdf",
          descriptionurl: "https://commons.wikimedia.org/wiki/File:Skipped_document.pdf",
          mime: "application/pdf",
        }],
      },
    ],
  },
}, "cinematic portrait");
assert(publicReferenceResults.length === 1, "Wikimedia parser should keep image results only.");
assert(publicReferenceResults[0].title === "Cinematic portrait reference.jpg", "Wikimedia parser should clean file titles.");
assert(publicReferenceResults[0].creator === "Jane Doe", "Wikimedia parser should clean metadata HTML.");
assert(publicReferenceResults[0].privacy.derivedFromPromptOnly === true, "Public references should be prompt-only derived.");

const openverseReferenceResults = parseOpenverseSearchResponse({
  results: [
    {
      id: "ov_99",
      title: "Cinematic street portrait",
      foreign_landing_url: "https://example.org/photos/cinematic-street-portrait",
      url: "https://images.example.org/cinematic-street-portrait.jpg",
      thumbnail: "https://images.example.org/thumbs/cinematic-street-portrait.jpg",
      license: "by",
      license_version: "4.0",
      creator: "<strong>Open Photographer</strong>",
      mature: false,
    },
    {
      id: "ov_mature",
      title: "Skipped mature result",
      url: "https://images.example.org/mature.jpg",
      mature: true,
    },
  ],
}, "cinematic portrait");
assert(openverseReferenceResults.length === 1, "Openverse parser should skip mature results.");
assert(openverseReferenceResults[0].source === "openverse", "Openverse parser should mark source correctly.");
assert(openverseReferenceResults[0].license === "CC BY 4.0", "Openverse parser should format Creative Commons license labels.");
assert(openverseReferenceResults[0].creator === "Open Photographer", "Openverse parser should clean creator HTML.");
assert(openverseReferenceResults[0].mimeType === "image/jpeg", "Openverse parser should infer common image MIME types.");

const rankedReferences = rankOnlineInspirationResults([
  {
    id: "wikimedia_commons_logo",
    source: "wikimedia_commons",
    query: inspirationRequest.queries[0],
    title: "Portrait location map icon.svg",
    pageUrl: "https://commons.wikimedia.org/wiki/File:Portrait_location_map_icon.svg",
    thumbnailUrl: "https://upload.wikimedia.org/wikipedia/commons/thumb/map.svg/640px-map.svg.png",
    imageUrl: "https://upload.wikimedia.org/wikipedia/commons/map.svg",
    mimeType: "image/svg+xml",
    privacy: publicReferenceResults[0].privacy,
  },
  publicReferenceResults[0],
  openverseReferenceResults[0],
], inspirationRequest);
assert(rankedReferences[0].id === publicReferenceResults[0].id, "Ranking should favor relevant photographic results over icon-like files.");
assert(rankedReferences[1].source === "openverse", "Ranking should diversify top public references across providers.");

const providerHealthSnapshot = makeOnlineInspirationHealthSnapshot({
  planId: inspirationRequest.planId,
  source: inspirationRequest.source,
  providers: [
    makeOnlineInspirationProviderHealth("wikimedia_commons", publicReferenceResults.length, undefined, "2026-08-29T00:00:00.000Z"),
    makeOnlineInspirationProviderHealth("openverse", 0, "failed", "2026-08-29T00:00:00.000Z", "Provider request failed"),
  ],
  checkedAt: "2026-08-29T00:00:00.000Z",
});
assert(providerHealthSnapshot.status === "degraded", "Provider health should report partial public-source failures.");
assert(providerHealthSnapshot.totalResultCount === 1, "Provider health should count usable public references.");
assert(providerHealthSnapshot.privacy.singlePhoneOnly === true, "Provider health must remain single-phone.");
assert(providerHealthSnapshot.privacy.sendsRawCameraFrame === false, "Provider health must not upload camera frames.");
assert(providerHealthSnapshot.providers[0].privacy.derivedFromPromptOnly === true, "Provider health must be prompt-only derived.");
assert(providerHealthSnapshot.providers[1].message === "Provider request failed", "Provider health should expose sanitized failure context.");

const availableProviderHealthSnapshot = makeOnlineInspirationHealthSnapshot({
  planId: inspirationRequest.planId,
  source: inspirationRequest.source,
  providers: [
    makeOnlineInspirationProviderHealth("wikimedia_commons", publicReferenceResults.length, undefined, "2026-08-29T00:00:00.000Z"),
    makeOnlineInspirationProviderHealth("openverse", openverseReferenceResults.length, undefined, "2026-08-29T00:00:00.000Z"),
  ],
  checkedAt: "2026-08-29T00:00:00.000Z",
});
const creativeProviderGate = makeCreativeInterpretationProviderHealthGate(creativeRequest, providerHealthSnapshot);
assert(creativeProviderGate.canRunProvider === true, "Creative provider gate should allow degraded health with safe public references.");
assert(creativeProviderGate.providerHealthStatus === "degraded", "Creative provider gate should preserve the public-source health status.");
assert(creativeProviderGate.publicReferenceCount === providerHealthSnapshot.totalResultCount, "Creative provider gate should count public references.");
assert(creativeProviderGate.privacy.sendsRawCameraFrame === false, "Creative provider gate must not allow raw live frames.");
assert(creativeProviderGate.privacy.sendsPrivatePhoto === false, "Creative provider gate must not allow private photos.");
assert(creativeProviderGate.privacy.sendsIdentityData === false, "Creative provider gate must not allow identity data.");
assert(creativeProviderGate.privacy.sendsPreciseLocation === false, "Creative provider gate must not allow precise location.");
assert(creativeProviderGate.privacy.sendsRawLearningEvents === false, "Creative provider gate must not allow raw learning events.");
const creativeResponse = makeHealthGatedCreativeInterpretationResponse(
  creativePlan,
  providerHealthSnapshot,
  "online_reasoning",
  64,
  "2026-08-29T00:00:00.000Z"
);
assert(creativeResponse.status === "completed", "Creative adapter should return a completed response when health and payload are safe.");
assert(creativeResponse.provider === "online_reasoning", "Creative adapter should run against the requested provider type.");
assert(creativeResponse.maxResponseWords === 64, "Creative adapter should preserve the clamped response budget.");
assert(creativeResponse.payloadAudit.safeToSend === true, "Creative adapter response should retain the payload audit.");
assert(creativeResponse.healthGate.canRunProvider === true, "Creative adapter response should retain the passing health gate.");
assert(creativeResponse.guidance.some((item) => item.includes("Stay Capture-Realistic")), "Creative adapter should preserve safety guidance.");
assert(creativeResponse.privacy.usesAuditedPayload === true, "Creative adapter must use the audited request path.");
assert(creativeResponse.privacy.usesProviderHealthGate === true, "Creative adapter must use the provider health gate.");
assert(creativeResponse.privacy.uploadsLiveCameraFrame === false, "Creative adapter must not upload live frames.");
assert(creativeResponse.privacy.sendsPrivatePhoto === false, "Creative adapter must not send private photos.");
assert(creativeResponse.privacy.sendsIdentityData === false, "Creative adapter must not send identity data.");
assert(creativeResponse.privacy.sendsRawLearningEvents === false, "Creative adapter must not send raw learning events.");
const openAIPayload = makeOpenAICreativeInterpretationResponsesPayload(creativeRequest, {
  model: "gpt-5.6-luna",
  allowsWebSearch: true,
  maxToolCalls: 8,
});
assert(openAICreativeInterpretationDefaults.endpoint === "https://api.openai.com/v1/responses", "OpenAI provider should target the Responses API endpoint.");
assert(openAIPayload.model === "gpt-5.6-luna", "OpenAI payload should use the configured model.");
assert(openAIPayload.store === false, "OpenAI payload should disable response storage for creative interpretation.");
assert(openAIPayload.max_tool_calls === 4, "OpenAI payload should clamp web search tool calls.");
assert(openAIPayload.tool_choice === "auto", "OpenAI payload should let the provider decide when web search helps.");
assert(openAIPayload.tools[0].type === "web_search", "OpenAI payload should use web search only as a built-in public-source tool.");
assert(openAIPayload.input.includes("Capture-Realistic"), "OpenAI payload should preserve capture-realistic guidance.");
assert(!openAIPayload.input.includes("raw_live_camera_feed"), "OpenAI payload must not include raw-frame blocklist tokens.");
assert(!openAIPayload.input.includes("private_photo"), "OpenAI payload must not include private-photo blocklist tokens.");
assert(openAIPayload.text.format.type === "json_schema", "OpenAI payload should request structured JSON output.");
assert(openAIPayload.text.format.strict === true, "OpenAI payload should require strict structured output.");
assert(openAIPayload.text.format.schema.additionalProperties === false, "OpenAI structured output should reject extra keys.");
assert(openAIPayload.text.format.schema.required.join(",") === "headline,guidance", "OpenAI structured output should require headline and guidance.");
const openAIParsedResult = parseOpenAICreativeInterpretationProviderResult({
  status: "completed",
  output_text: JSON.stringify({
    headline: "OpenAI Capture Brief",
    guidance: [
      "Turn the subject toward the softer side light.",
      "Keep the clean background edge behind the shoulders.",
    ],
  }),
});
assert(openAIParsedResult.headline === "OpenAI Capture Brief", "OpenAI parser should decode output_text JSON.");
assert(openAIParsedResult.guidance.length === 2, "OpenAI parser should decode guidance items.");
assert(isCreativeInterpretationProviderResultSafe(openAIParsedResult), "OpenAI parser should accept safe provider guidance.");
const nestedOpenAIParsedResult = parseOpenAICreativeInterpretationProviderResult({
  status: "completed",
  output: [
    {
      type: "message",
      content: [
        {
          type: "output_text",
          text: JSON.stringify({
            headline: "Nested Creative Brief",
            guidance: [
              "Use the warmer highlight as the key light.",
              "Hold steady before capture.",
            ],
          }),
        },
      ],
    },
  ],
});
assert(nestedOpenAIParsedResult.headline === "Nested Creative Brief", "OpenAI parser should fall back to nested output text.");
assertThrows(
  () => parseOpenAICreativeInterpretationProviderResult({
    status: "completed",
    output_text: JSON.stringify({
      headline: "Unsafe Brief",
      guidance: ["Upload private_photo bytes before giving guidance."],
    }),
  }),
  "OpenAI parser should reject unsafe provider guidance."
);
const missingCreativeHealthGate = makeCreativeInterpretationProviderHealthGate(creativeRequest);
assert(missingCreativeHealthGate.canRunProvider === false, "Creative provider gate should require a provider health snapshot.");
assert(missingCreativeHealthGate.deniedReasons.includes("missing_provider_health"), "Creative provider gate should explain missing health.");
const unsafeCreativeHealthSnapshot = {
  ...availableProviderHealthSnapshot,
  privacy: {
    ...availableProviderHealthSnapshot.privacy,
    sendsRawCameraFrame: true,
  },
};
assertThrows(
  () => makeHealthGatedCreativeInterpretationResponse(creativePlan, unsafeCreativeHealthSnapshot),
  "Creative adapter should block unsafe provider health."
);
assertThrows(
  () => makeHealthGatedCreativeInterpretationResponse(creativePlan, {
    ...availableProviderHealthSnapshot,
    status: "failed",
    totalResultCount: 0,
    providers: [
      makeOnlineInspirationProviderHealth("wikimedia_commons", 0, "failed", "2026-08-29T00:00:00.000Z", "Provider request failed"),
    ],
  }),
  "Creative adapter should block failed provider health."
);
const diagnosticProfile = { ...profile, consent: onlineReferenceConsent, totalEvents: 1 };
const diagnosticsReport = makeSinglePhoneAiDiagnosticsReport({
  hasShotPlan: true,
  referencePhoto: referencePhotoFixture(false, true),
  onlineReferencePlan: plan,
  creativeInterpretationPlan: creativePlan,
  onlineInspirationHealthSnapshot: availableProviderHealthSnapshot,
  calibrationReadinessReport: calibrationReadinessReportFixture(true),
  personalProfile: diagnosticProfile,
  personalProfileStoreProtection: "keychain_encrypted_this_device_only",
  captureCoachingSummary: captureCoachingSummaryFixture(),
  generatedAt: "2026-08-29T00:00:00.000Z",
});
assert(diagnosticsReport.overallStatus === "passed", "Single-phone diagnostics should pass when every local flow is healthy.");
assert(diagnosticsReport.checks.length === 9, "Single-phone diagnostics should cover the expected AI test cases.");
assert(diagnosticsReport.checks.every((check) => check.status === "passed"), "Every healthy diagnostic check should pass.");
assert(diagnosticsReport.checks.find((check) => check.id === "creative_interpretation").detail === `${creativePlan.suggestions.length} suggestions`, "Diagnostics should verify creative interpretation.");
assert(diagnosticsReport.checks.find((check) => check.id === "calibration_readiness").detail === "24/24 captures", "Diagnostics should confirm real-capture calibration readiness.");
assert(diagnosticsReport.checks.find((check) => check.id === "learning_store").detail === "Keychain encrypted", "Diagnostics should confirm encrypted learning storage.");
assert(diagnosticsReport.privacy.singlePhoneOnly === true, "Diagnostics report must stay single-phone.");
assert(diagnosticsReport.privacy.uploadsLiveCameraFrame === false, "Diagnostics report must not upload live camera frames.");

const unsafeHealthSnapshot = {
  ...availableProviderHealthSnapshot,
  privacy: {
    ...availableProviderHealthSnapshot.privacy,
    sendsRawCameraFrame: true,
  },
};
const blockedDiagnosticsReport = makeSinglePhoneAiDiagnosticsReport({
  hasShotPlan: true,
  referencePhoto: referencePhotoFixture(true, true),
  onlineReferencePlan: plan,
  creativeInterpretationPlan: {
    ...creativePlan,
    inputSummary: [...creativePlan.inputSummary, "Prompt: private_photo"],
    privacy: {
      ...creativePlan.privacy,
      sendsPrivatePhoto: true,
    },
  },
  onlineInspirationHealthSnapshot: unsafeHealthSnapshot,
  personalProfile: diagnosticProfile,
  captureCoachingSummary: captureCoachingSummaryFixture(),
  generatedAt: "2026-08-29T00:00:00.000Z",
});
assert(blockedDiagnosticsReport.overallStatus === "blocked", "Single-phone diagnostics should block unsafe payloads.");
assert(blockedDiagnosticsReport.checks.find((check) => check.id === "reference_popup").status === "blocked", "Diagnostics should block cloud-analyzed references.");
assert(blockedDiagnosticsReport.checks.find((check) => check.id === "creative_interpretation").status === "blocked", "Diagnostics should block creative plans that send private photos.");
assert(blockedDiagnosticsReport.checks.find((check) => check.id === "online_provider_health").status === "blocked", "Diagnostics should block provider health that uploads camera frames.");

const thumbnailCache = makeThumbnailMemoryCache(1);
thumbnailCache.set("https://example.test/first.jpg", new Uint8Array([1]));
thumbnailCache.set("https://example.test/second.jpg", new Uint8Array([2]));
assert(!thumbnailCache.get("https://example.test/first.jpg"), "Thumbnail cache should evict oldest entries.");
assert(thumbnailCache.get("https://example.test/second.jpg")[0] === 2, "Thumbnail cache should keep the latest entry.");

console.log(JSON.stringify({
  personalLearning: true,
  learningInsight: learningInsight.status,
  correctiveFeedbackLearning: true,
  localProfileStorage: storageSnapshot.privacy,
  onlineReferencePlan: plan.reason,
  creativeInterpretationPlan: creativePlan.reason,
  creativePayloadAudit: creativePayloadAudit.safeToSend,
  creativeProviderGate: creativeProviderGate.canRunProvider,
  onlineSourceAdapter: [...new Set(rankedReferences.map((result) => result.source))].join("+"),
  onlineProviderHealth: providerHealthSnapshot.status,
  singlePhoneDiagnostics: diagnosticsReport.overallStatus,
  onlineRanking: rankedReferences[0].id,
  privacy: plan.privacy,
  status: "passed",
}, null, 2));

function emptyProfile(consent) {
  return {
    version: "1.0",
    consent,
    totalEvents: 0,
    domainCounts: {},
    styleAffinities: {},
    colorAffinities: {},
    framingAffinities: {},
    guidanceReasonAffinities: {},
    requirementAffinities: {},
    onlineReferenceUsageCount: 0,
  };
}

function sanitizeProfileForLocalStorage(profile) {
  return {
    version: "1.0",
    consent: {
      learningEnabled: profile.consent.learningEnabled,
      onlineReferencesAllowed: profile.consent.onlineReferencesAllowed,
      cloudPersonalizationSyncAllowed: false,
    },
    totalEvents: clampCount(profile.totalEvents),
    domainCounts: sanitizeCountMap(profile.domainCounts, ["portrait", "landscape", "travel", "lifestyle", "night", "reference"], 6),
    styleAffinities: sanitizeAffinityMap(profile.styleAffinities, ["natural", "cinematic", "professional", "travel", "portrait", "night", "sky", "lifestyle", "custom"], 9),
    colorAffinities: sanitizeAffinityMap(profile.colorAffinities, ["natural", "warm_highlights", "cool_shadows", "warm_highlights_cool_shadows", "high_contrast", "low_contrast"], 6),
    framingAffinities: sanitizeAffinityMap(profile.framingAffinities, ["close", "medium", "wide", "environmental", "three_quarter", "symmetrical", "rule_of_thirds"], 7),
    guidanceReasonAffinities: sanitizeAffinityMap(profile.guidanceReasonAffinities, [
      "improve_subject_background_separation",
      "level_horizon",
      "protect_highlights",
      "improve_face_light",
      "reduce_clutter",
      "match_reference",
      "improve_pose",
      "increase_sky",
      "reduce_motion_blur",
      "ready_to_capture",
    ], 10),
    requirementAffinities: sanitizeAffinityMap(profile.requirementAffinities, undefined, 48),
    onlineReferenceUsageCount: clampCount(profile.onlineReferenceUsageCount),
  };
}

function encodePersonalVisualPreferenceProfileForLocalStorage(profile) {
  const json = JSON.stringify(sanitizeProfileForLocalStorage(profile));
  if (json.length > personalVisualProfileStoragePolicy.maxStoredProfileBytes) {
    throw new Error("personal_visual_profile_too_large");
  }
  return json;
}

function decodePersonalVisualPreferenceProfileFromLocalStorage(json) {
  if (json.length > personalVisualProfileStoragePolicy.maxStoredProfileBytes) {
    throw new Error("personal_visual_profile_too_large");
  }
  return sanitizeProfileForLocalStorage(JSON.parse(json));
}

function makePersonalVisualProfileStorageSnapshot(profile) {
  const storedProfile = sanitizeProfileForLocalStorage(profile);
  return {
    storageKey: personalVisualProfileStoragePolicy.storageKey,
    storageProtection: personalVisualProfileStoragePolicy.preferredProtection,
    profile: storedProfile,
    estimatedJsonBytes: JSON.stringify(storedProfile).length,
    privacy: personalVisualProfileStoragePolicy.privacy,
  };
}

function updatedProfile(profile, event, consent = profile.consent) {
  if (!consent.learningEnabled || !canLearnLocally(event)) {
    return { ...profile, consent };
  }

  const signal = outcomeSignal(event);
  const next = {
    ...profile,
    consent,
    totalEvents: profile.totalEvents + 1,
    domainCounts: { ...profile.domainCounts, [event.domain]: (profile.domainCounts[event.domain] ?? 0) + 1 },
    styleAffinities: { ...profile.styleAffinities },
    colorAffinities: { ...profile.colorAffinities },
    framingAffinities: { ...profile.framingAffinities },
    guidanceReasonAffinities: { ...profile.guidanceReasonAffinities },
    requirementAffinities: { ...profile.requirementAffinities },
    onlineReferenceUsageCount: profile.onlineReferenceUsageCount + (event.onlineReferenceUsed ? 1 : 0),
  };

  if (event.selectedStyle) bump(next.styleAffinities, event.selectedStyle, 0.06 * signal);
  if (event.selectedColorIntent) bump(next.colorAffinities, event.selectedColorIntent, 0.05 * signal);
  if (event.selectedFraming) bump(next.framingAffinities, event.selectedFraming, 0.05 * signal);
  for (const requirement of event.promptRequirements) bump(next.requirementAffinities, requirement, 0.04 * signal);
  if (event.acceptedGuidanceReason) bump(next.guidanceReasonAffinities, event.acceptedGuidanceReason, 0.08 * Math.max(0.25, signal));
  if (event.rejectedGuidanceReason) bump(next.guidanceReasonAffinities, event.rejectedGuidanceReason, -0.08 * Math.max(0.25, Math.abs(signal)));
  if (event.customerCorrectionReason) {
    const correctionSignal = Math.max(0.4, Math.abs(signal));
    bump(next.guidanceReasonAffinities, event.customerCorrectionReason, 0.10 * correctionSignal);
    bump(next.requirementAffinities, `customer_correction_${event.customerCorrectionReason}`, 0.05 * correctionSignal);
  }

  return next;
}

function guidanceCalibration(profile) {
  if (!profile.consent.learningEnabled) {
    return { globalReasonBoosts: {}, domainReasonBoosts: {} };
  }

  return {
    globalReasonBoosts: Object.fromEntries(
      Object.entries(profile.guidanceReasonAffinities)
        .filter(([, affinity]) => (affinity ?? 0) > 0)
        .map(([reason, affinity]) => [reason, Math.min(0.04, (affinity ?? 0) * 0.04)])
    ),
    domainReasonBoosts: {},
  };
}

function makePersonalVisualLearningInsight(profile, maxSignals = 8) {
  const guidanceBoosts = guidanceCalibration(profile).globalReasonBoosts;
  const topSignals = learningSignals(profile).slice(0, Math.max(0, maxSignals));
  const status = learningInsightStatus(profile, topSignals.length > 0);

  return {
    status,
    headline: learningInsightHeadline(profile, status),
    eventCount: Math.max(0, profile.totalEvents ?? 0),
    topSignals,
    guidanceBoosts: Object.fromEntries(
      Object.entries(guidanceBoosts).filter(([, boost]) => Number.isFinite(boost) && boost > 0)
    ),
    onlineReferenceUsageCount: Math.max(0, profile.onlineReferenceUsageCount ?? 0),
    privacy: {
      singlePhoneOnly: true,
      storesRawPhoto: false,
      uploadsLiveCameraFrame: false,
      storesIdentityData: false,
      cloudPersonalizationSyncAllowed: false,
    },
  };
}

function learningInsightStatus(profile, hasSignals) {
  if (!profile.consent.learningEnabled) return "disabled";
  if ((profile.totalEvents ?? 0) < 3 || !hasSignals) return "warming_up";
  return "personalized";
}

function learningInsightHeadline(profile, status) {
  if (status === "disabled") return "Local learning is off";
  if (status === "warming_up") {
    return (profile.totalEvents ?? 0) === 0
      ? "Ready to learn from local choices"
      : `Learning from ${profile.totalEvents} local events`;
  }
  return `Personalized from ${profile.totalEvents} local events`;
}

function learningSignals(profile) {
  const signals = [];
  const domainSignal = topCountSignal(profile.domainCounts, "domain", profile.totalEvents);
  if (domainSignal) signals.push(domainSignal);

  appendTopAffinitySignal(signals, profile.styleAffinities, "style");
  appendTopAffinitySignal(signals, profile.colorAffinities, "color");
  appendTopAffinitySignal(signals, profile.framingAffinities, "framing");
  appendTopAffinitySignal(signals, profile.guidanceReasonAffinities, "guidance");
  appendTopAffinitySignal(signals, profile.requirementAffinities, "requirement");

  if ((profile.onlineReferenceUsageCount ?? 0) > 0) {
    signals.push({
      id: "online_reference_public_inspiration",
      category: "online_reference",
      label: "Public Inspiration",
      score: Math.min(1, profile.onlineReferenceUsageCount / Math.max(1, profile.totalEvents ?? 0)),
    });
  }

  return signals.sort((a, b) => b.score === a.score ? a.label.localeCompare(b.label) : b.score - a.score);
}

function topCountSignal(values, category, eventCount) {
  const top = Object.entries(values ?? {})
    .filter(([, value]) => value > 0)
    .sort(([lhsKey, lhsValue], [rhsKey, rhsValue]) => rhsValue === lhsValue ? lhsKey.localeCompare(rhsKey) : rhsValue - lhsValue)[0];
  if (!top) return undefined;

  const [key, value] = top;
  return {
    id: `${category}_${key}`,
    category,
    label: displayLearningKey(key),
    score: Math.min(1, value / Math.max(1, eventCount ?? 0)),
  };
}

function appendTopAffinitySignal(signals, values, category) {
  const top = Object.entries(values ?? {})
    .filter(([, value]) => value > 0)
    .sort(([lhsKey, lhsValue], [rhsKey, rhsValue]) => rhsValue === lhsValue ? lhsKey.localeCompare(rhsKey) : rhsValue - lhsValue)[0];
  if (!top) return;

  const [key, value] = top;
  signals.push({
    id: `${category}_${key}`,
    category,
    label: displayLearningKey(key),
    score: Math.min(1, Math.max(0, Number.isFinite(value) ? value : 0)),
  });
}

function displayLearningKey(key) {
  return String(key)
    .replace(/^customer_correction_/, "")
    .replace(/_/g, " ")
    .replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function makeOnlineReferencePlan(shotSpec, prompt, profile, consent = profile.consent) {
  if (!consent.onlineReferencesAllowed) return undefined;

  const normalizedPrompt = prompt.toLowerCase();
  const explicitReferenceRequest = containsAny(normalizedPrompt, ["reference", "inspiration", "like this", "online", "trend"]);
  const specializedStyle = shotSpec.style.name !== "natural" || containsAny(normalizedPrompt, ["instagram", "luxury", "professional", "cinematic"]);
  const needsHistory = profile.totalEvents < 3 && specializedStyle;
  if (!explicitReferenceRequest && !specializedStyle && !needsHistory) return undefined;

  const reason = explicitReferenceRequest
    ? "explicit_user_request"
    : needsHistory
      ? "insufficient_personal_history"
      : "specialized_style";

  return {
    id: `online_reference_${shotSpec.id}`,
    reason,
    searchQueries: uniqueNonEmpty([
      `${shotSpec.style.name} ${shotSpec.domain} phone photography reference`,
      `${shotSpec.domain} ${shotSpec.composition.framing} ${shotSpec.composition.backgroundPriority ?? "clean"} photography ideas`,
      compactPromptQuery(normalizedPrompt),
    ]),
    allowedInputs: ["prompt_text", "shot_spec_summary", "device_capability_summary"],
    mustNotSend: ["raw_live_camera_feed", "private_photo", "face_identity", "precise_location_without_consent"],
    userDisclosure: "LensPilot can look up public inspiration using your prompt, but it will not upload your live camera feed or private photos.",
    privacy: {
      singlePhoneOnly: true,
      requiresUserConsent: true,
      sendsRawCameraFrame: false,
      sendsPrivatePhoto: false,
      sendsIdentityData: false,
    },
  };
}

function makeCreativeInterpretationPlan(shotSpec, prompt, profile, onlineReferencePlan, consent = profile.consent) {
  if (!consent.onlineReferencesAllowed) return undefined;

  const normalizedPrompt = prompt.toLowerCase();
  const explicitCreativeRequest = containsAny(normalizedPrompt, [
    "creative",
    "interpret",
    "brief",
    "inspiration",
    "reference",
    "online",
    "trend",
    "make it look",
    "style",
  ]);
  const specializedStyle = shotSpec.style.name !== "natural" ||
    Boolean(shotSpec.style.mood) ||
    containsAny(normalizedPrompt, ["cinematic", "professional", "luxury", "dramatic", "moody", "instagram"]);
  const insight = makePersonalVisualLearningInsight(profile, 3);
  const hasLearnedSignals = consent.learningEnabled && profile.totalEvents >= 3 && insight.topSignals.length > 0;

  if (!explicitCreativeRequest && !specializedStyle && !onlineReferencePlan && !hasLearnedSignals) return undefined;

  const reason = explicitCreativeRequest
    ? "explicit_user_request"
    : onlineReferencePlan
      ? "online_inspiration"
      : hasLearnedSignals
        ? "learned_preference"
        : "specialized_style";

  const allowedInputs = [
    "prompt_text",
    "shot_spec_summary",
    "device_capability_summary",
  ];
  if (hasLearnedSignals) allowedInputs.push("learned_preference_summary");
  if (onlineReferencePlan) allowedInputs.push("public_reference_summary");

  return {
    id: `creative_interpretation_${shotSpec.id}`,
    reason,
    inputSummary: creativeInputSummary(shotSpec, normalizedPrompt, profile, hasLearnedSignals, Boolean(onlineReferencePlan)),
    suggestions: creativeSuggestions(shotSpec, normalizedPrompt, profile, hasLearnedSignals, Boolean(onlineReferencePlan)),
    allowedInputs,
    mustNotSend: [
      "raw_live_camera_feed",
      "private_photo",
      "face_identity",
      "precise_location_without_consent",
      "raw_learning_events",
    ],
    userDisclosure: "LensPilot can interpret the shot using prompt, plan, learned aggregate preferences, and public-reference summaries only. It will not upload your live camera feed or private photos.",
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
  };
}

function creativeInputSummary(shotSpec, prompt, profile, includeLearnedSignals, includePublicReferences) {
  const summary = [
    `Scene: ${displayLearningKey(shotSpec.domain)}`,
    `Style: ${displayLearningKey(shotSpec.style.name)}`,
    `Framing: ${displayLearningKey(shotSpec.composition.framing)}`,
  ];

  if (shotSpec.style.colorIntent) {
    summary.push(`Color: ${displayLearningKey(shotSpec.style.colorIntent)}`);
  }

  const promptSummary = compactPromptQuery(prompt);
  if (promptSummary) {
    summary.push(`Prompt: ${promptSummary}`);
  }

  if (includeLearnedSignals) {
    const topSignal = makePersonalVisualLearningInsight(profile, 1).topSignals[0];
    if (topSignal) {
      summary.push(`Learned: ${topSignal.label}`);
    }
  }

  if (includePublicReferences) {
    summary.push("References: Public inspiration summaries");
  }

  return uniqueNonEmpty(summary);
}

function creativeSuggestions(shotSpec, prompt, profile, includeLearnedSignals, includePublicReferences) {
  const suggestions = [];
  const append = (suggestion) => {
    if (!suggestions.some((existing) => existing.id === suggestion.id)) {
      suggestions.push(suggestion);
    }
  };

  switch (shotSpec.style.name) {
    case "cinematic":
      append({
        id: "cinematic_side_light",
        category: "lighting",
        title: "Shape the Light",
        instruction: "Favor side light or backlight, then keep face detail readable.",
      });
      append({
        id: "cinematic_color_separation",
        category: "color",
        title: "Separate Color",
        instruction: "Look for warm highlights with cooler shadow separation.",
      });
      break;
    case "professional":
      append({
        id: "professional_clean_lines",
        category: "composition",
        title: "Clean the Frame",
        instruction: "Keep the background simple and vertical lines straight.",
      });
      break;
    case "travel":
      append({
        id: "travel_place_cue",
        category: "composition",
        title: "Keep the Place Cue",
        instruction: "Include one recognizable location detail without crowding the subject.",
      });
      break;
    case "night":
      append({
        id: "night_stability",
        category: "lighting",
        title: "Stabilize the Shot",
        instruction: "Use bright edges or signage, then hold the phone steady before capture.",
      });
      break;
    case "sky":
      append({
        id: "sky_highlight_guard",
        category: "composition",
        title: "Protect the Sky",
        instruction: "Place the horizon low enough for sky drama while protecting highlights.",
      });
      break;
    case "portrait":
    case "lifestyle":
      append({
        id: "portrait_subject_space",
        category: "lens",
        title: "Give Subject Space",
        instruction: "Step back slightly for flattering perspective and cleaner separation.",
      });
      break;
  }

  switch (shotSpec.style.mood) {
    case "dramatic":
    case "moody":
      append({
        id: "mood_shadow_control",
        category: "lighting",
        title: "Use Shadows",
        instruction: "Let shadows add shape, but keep the main subject easy to read.",
      });
      break;
    case "luxury":
      append({
        id: "mood_luxury_polish",
        category: "color",
        title: "Polish the Palette",
        instruction: "Choose clean textures, warm highlights, and fewer background colors.",
      });
      break;
    case "bright":
    case "soft":
      append({
        id: "mood_soft_light",
        category: "lighting",
        title: "Soften Contrast",
        instruction: "Find open shade or window light so skin and highlights stay gentle.",
      });
      break;
    case "documentary":
      append({
        id: "mood_documentary_context",
        category: "composition",
        title: "Keep Context",
        instruction: "Leave enough environment in frame to explain the moment.",
      });
      break;
  }

  if (shotSpec.subject?.primary === "person" || shotSpec.subject?.primary === "people") {
    append({
      id: "person_face_priority",
      category: "lighting",
      title: "Prioritize Face Light",
      instruction: "Turn the subject toward cleaner light before refining background.",
    });
  }

  if (shotSpec.composition.skyPriority === "high") {
    append({
      id: "composition_more_sky",
      category: "composition",
      title: "Leave Sky Room",
      instruction: "Tilt just enough to add sky while keeping the subject anchored.",
    });
  }

  if (includePublicReferences || containsAny(prompt, ["reference", "inspiration", "online", "trend"])) {
    append({
      id: "reference_compare_public_sources",
      category: "reference",
      title: "Compare References",
      instruction: "Use public references for light, angle, and framing cues only.",
    });
  }

  if (includeLearnedSignals) {
    const topSignal = makePersonalVisualLearningInsight(profile, 1).topSignals[0];
    if (topSignal) {
      append({
        id: `learned_preference_${topSignal.id}`,
        category: "composition",
        title: "Respect Learned Taste",
        instruction: `Blend the learned ${topSignal.label.toLowerCase()} preference into this shot.`,
      });
    }
  }

  const safetySuggestion = {
    id: "capture_realistic_boundary",
    category: "safety",
    title: "Stay Capture-Realistic",
    instruction: "Treat this as a camera brief; avoid promising generated edits in preview.",
  };
  append(safetySuggestion);

  const requiredSuggestionIds = new Set(["reference_compare_public_sources", safetySuggestion.id]);
  const requiredSuggestions = suggestions.filter((suggestion) => requiredSuggestionIds.has(suggestion.id));
  const optionalSuggestions = suggestions.filter((suggestion) => !requiredSuggestionIds.has(suggestion.id));
  return [
    ...optionalSuggestions.slice(0, Math.max(0, 6 - requiredSuggestions.length)),
    ...requiredSuggestions,
  ];
}

function makeOnlineInspirationRequest(plan, perQueryLimit = 4) {
  if (
    !plan.privacy.singlePhoneOnly ||
    !plan.privacy.requiresUserConsent ||
    plan.privacy.sendsRawCameraFrame ||
    plan.privacy.sendsPrivatePhoto ||
    plan.privacy.sendsIdentityData
  ) {
    throw new Error("unsafe_online_reference_plan");
  }

  return {
    planId: plan.id,
    queries: uniqueNonEmpty(plan.searchQueries).slice(0, 3),
    perQueryLimit: Math.min(10, Math.max(1, perQueryLimit)),
    source: "public_sources",
    privacy: {
      singlePhoneOnly: true,
      requiresUserConsent: true,
      sendsRawCameraFrame: false,
      sendsPrivatePhoto: false,
      sendsIdentityData: false,
      sendsPreciseLocation: false,
    },
  };
}

function makeCreativeInterpretationPayloadAudit(plan) {
  const blockedTermsDetected = blockedCreativeInterpretationPayloadTerms(plan);
  const deniedReasons = [];

  if (!isCreativeInterpretationPrivacySafe(plan.privacy)) {
    deniedReasons.push("unsafe_privacy");
  }

  if (!requiredCreativeInterpretationMustNotSendTerms.every((term) => plan.mustNotSend.includes(term))) {
    deniedReasons.push("missing_required_blocklist");
  }

  if (plan.allowedInputs.length === 0) {
    deniedReasons.push("empty_allowed_inputs");
  }

  if (plan.inputSummary.length === 0) {
    deniedReasons.push("empty_safe_summary");
  }

  if (plan.suggestions.length === 0) {
    deniedReasons.push("empty_suggestions");
  }

  if (blockedTermsDetected.length > 0) {
    deniedReasons.push("blocked_term_detected");
  }

  const uniqueDeniedReasons = [...new Set(deniedReasons)].sort();

  return {
    safeToSend: uniqueDeniedReasons.length === 0,
    deniedReasons: uniqueDeniedReasons,
    blockedTermsDetected,
    allowedInputCount: Math.max(0, plan.allowedInputs.length),
    summaryCount: Math.max(0, plan.inputSummary.length),
    suggestionCount: Math.max(0, plan.suggestions.length),
  };
}

function makeCreativeInterpretationRequest(plan, provider = "online_reasoning", maxResponseWords = 120) {
  const payloadAudit = makeCreativeInterpretationPayloadAudit(plan);
  if (!payloadAudit.safeToSend) {
    throw new Error(`unsafe_creative_interpretation_plan:${payloadAudit.deniedReasons.join(",")}`);
  }

  return {
    planId: plan.id,
    provider,
    inputSummary: plan.inputSummary,
    suggestionBriefs: plan.suggestions.map((suggestion) => `${suggestion.title}: ${suggestion.instruction}`),
    allowedInputs: plan.allowedInputs,
    maxResponseWords: Math.min(240, Math.max(40, Math.trunc(maxResponseWords))),
    payloadAudit,
    privacy: plan.privacy,
  };
}

function makeOnlineInspirationProviderHealth(
  source,
  resultCount,
  status = undefined,
  checkedAt = new Date().toISOString(),
  message = undefined
) {
  const safeResultCount = Number.isFinite(resultCount)
    ? Math.max(0, Math.floor(resultCount))
    : 0;
  const cleanedMessage = typeof message === "string" ? message.trim() : "";

  return {
    source,
    status: status ?? (safeResultCount > 0 ? "available" : "empty"),
    resultCount: safeResultCount,
    checkedAt,
    ...(cleanedMessage ? { message: cleanedMessage } : {}),
    privacy: {
      publicSourceOnly: true,
      derivedFromPromptOnly: true,
      storesRawPhoto: false,
      uploadsLiveCameraFrame: false,
      sendsIdentityData: false,
      sendsPreciseLocation: false,
    },
  };
}

function makeOnlineInspirationHealthSnapshot({ planId, source, providers, checkedAt = new Date().toISOString() }) {
  return {
    planId,
    source,
    status: aggregateOnlineInspirationHealthStatus(providers),
    checkedAt,
    totalResultCount: providers.reduce((total, provider) => total + provider.resultCount, 0),
    providers,
    privacy: {
      singlePhoneOnly: true,
      requiresUserConsent: true,
      sendsRawCameraFrame: false,
      sendsPrivatePhoto: false,
      sendsIdentityData: false,
      sendsPreciseLocation: false,
    },
  };
}

function aggregateOnlineInspirationHealthStatus(providers) {
  if (providers.length === 0) return "empty";

  const hasAvailableProvider = providers.some((provider) => provider.status === "available");
  const hasFailedProvider = providers.some((provider) => provider.status === "failed");

  if (hasAvailableProvider && hasFailedProvider) return "degraded";
  if (hasAvailableProvider) return "available";
  if (hasFailedProvider) return "failed";
  return "empty";
}

function makeCreativeInterpretationProviderHealthGate(request, healthSnapshot = undefined) {
  const deniedReasons = [];
  const privacy = {
    singlePhoneOnly: request.privacy.singlePhoneOnly && (healthSnapshot?.privacy.singlePhoneOnly ?? true),
    requiresUserConsent: request.privacy.requiresUserConsent && (healthSnapshot?.privacy.requiresUserConsent ?? true),
    sendsRawCameraFrame: request.privacy.sendsRawCameraFrame || (healthSnapshot?.privacy.sendsRawCameraFrame ?? false),
    sendsPrivatePhoto: request.privacy.sendsPrivatePhoto || (healthSnapshot?.privacy.sendsPrivatePhoto ?? false),
    sendsIdentityData: request.privacy.sendsIdentityData || (healthSnapshot?.privacy.sendsIdentityData ?? false),
    sendsPreciseLocation: request.privacy.sendsPreciseLocation || (healthSnapshot?.privacy.sendsPreciseLocation ?? false),
    sendsRawLearningEvents: request.privacy.sendsRawLearningEvents,
  };

  if (!request.payloadAudit.safeToSend) {
    deniedReasons.push("unsafe_request_payload");
  }

  if (!healthSnapshot) {
    deniedReasons.push("missing_provider_health");
    const uniqueDeniedReasons = [...new Set(deniedReasons)].sort();
    return {
      canRunProvider: false,
      deniedReasons: uniqueDeniedReasons,
      publicReferenceCount: 0,
      payloadAudit: request.payloadAudit,
      privacy,
    };
  }

  const hasSafeSnapshotPrivacy =
    privacy.singlePhoneOnly &&
    privacy.requiresUserConsent &&
    !privacy.sendsRawCameraFrame &&
    !privacy.sendsPrivatePhoto &&
    !privacy.sendsIdentityData &&
    !privacy.sendsPreciseLocation &&
    !privacy.sendsRawLearningEvents;
  const hasSafeProviderPrivacy = healthSnapshot.providers.every((provider) =>
    provider.privacy.publicSourceOnly &&
    provider.privacy.derivedFromPromptOnly &&
    !provider.privacy.storesRawPhoto &&
    !provider.privacy.uploadsLiveCameraFrame &&
    !provider.privacy.sendsIdentityData &&
    !provider.privacy.sendsPreciseLocation
  );

  if (!hasSafeSnapshotPrivacy || !hasSafeProviderPrivacy) {
    deniedReasons.push("unsafe_provider_health");
  }

  if (healthSnapshot.status === "failed") {
    deniedReasons.push("provider_unavailable");
  } else if (healthSnapshot.status === "empty") {
    deniedReasons.push("no_public_references");
  }

  if (healthSnapshot.totalResultCount <= 0) {
    deniedReasons.push("no_public_references");
  }

  const uniqueDeniedReasons = [...new Set(deniedReasons)].sort();
  return {
    canRunProvider: uniqueDeniedReasons.length === 0,
    deniedReasons: uniqueDeniedReasons,
    providerHealthStatus: healthSnapshot.status,
    publicReferenceCount: Math.max(0, healthSnapshot.totalResultCount),
    payloadAudit: request.payloadAudit,
    privacy,
  };
}

function makeHealthGatedCreativeInterpretationResponse(
  plan,
  healthSnapshot = undefined,
  provider = "online_reasoning",
  maxResponseWords = 120,
  generatedAt = new Date().toISOString()
) {
  const request = makeCreativeInterpretationRequest(plan, provider, maxResponseWords);
  const healthGate = makeCreativeInterpretationProviderHealthGate(request, healthSnapshot);

  if (!healthGate.canRunProvider) {
    throw new Error(`creative_interpretation_health_gate_blocked:${healthGate.deniedReasons.join(",")}`);
  }

  const guidance = creativeInterpretationGuidanceFromRequest(request);
  if (guidance.length === 0) {
    throw new Error("empty_creative_interpretation_provider_output");
  }
  if (!isCreativeInterpretationProviderResultSafe({
    headline: provider === "online_reasoning" ? "Provider-Ready Creative Brief" : "Local Creative Brief",
    guidance,
  })) {
    throw new Error("unsafe_creative_interpretation_provider_output");
  }

  return {
    id: `creative_interpretation_response_${request.planId}_${request.provider}`,
    planId: request.planId,
    provider: request.provider,
    status: "completed",
    headline: provider === "online_reasoning" ? "Provider-Ready Creative Brief" : "Local Creative Brief",
    guidance,
    maxResponseWords: request.maxResponseWords,
    generatedAt,
    payloadAudit: request.payloadAudit,
    healthGate,
    privacy: {
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
    },
  };
}

function makeSinglePhoneAiDiagnosticsReport({
  hasShotPlan,
  referencePhoto,
  onlineReferencePlan,
  creativeInterpretationPlan,
  onlineInspirationHealthSnapshot,
  calibrationReadinessReport,
  personalProfile,
  personalProfileStoreProtection = personalVisualProfileStoragePolicy.preferredProtection,
  captureCoachingSummary,
  generatedAt = new Date().toISOString(),
}) {
  const checks = [
    {
      id: "shot_planning",
      title: "Shot Planning",
      status: hasShotPlan ? "passed" : "attention",
      detail: hasShotPlan ? "Ready" : "Run a prompt first",
    },
    referencePopupDiagnosticCheck(referencePhoto),
    onlineReferencePlanDiagnosticCheck(onlineReferencePlan),
    creativeInterpretationDiagnosticCheck(creativeInterpretationPlan),
    onlineProviderHealthDiagnosticCheck(onlineInspirationHealthSnapshot),
    calibrationReadinessDiagnosticCheck(calibrationReadinessReport),
    localLearningDiagnosticCheck(personalProfile),
    learningStoreDiagnosticCheck(personalProfile, personalProfileStoreProtection),
    captureCoachingDiagnosticCheck(captureCoachingSummary),
  ];

  return {
    generatedAt,
    overallStatus: aggregateSinglePhoneAiDiagnosticsStatus(checks),
    checks,
    privacy: {
      singlePhoneOnly: true,
      storesRawPhoto: false,
      uploadsLiveCameraFrame: false,
      sendsIdentityData: false,
      sendsPreciseLocation: false,
    },
  };
}

function creativeInterpretationDiagnosticCheck(plan) {
  if (!plan) {
    return {
      id: "creative_interpretation",
      title: "Creative Plan",
      status: "attention",
      detail: "Not triggered",
    };
  }

  const payloadAudit = makeCreativeInterpretationPayloadAudit(plan);

  return {
    id: "creative_interpretation",
    title: "Creative Plan",
    status: payloadAudit.safeToSend ? "passed" : "blocked",
    detail: payloadAudit.safeToSend
      ? `${payloadAudit.suggestionCount} suggestions`
      : payloadAudit.deniedReasons[0]?.replace(/_/g, " ") ?? "Unsafe payload",
  };
}

function referencePhotoFixture(cloudAnalysisUsed, showCameraPopup) {
  return {
    id: "reference_diagnostic_test",
    source: "photo_library",
    localAssetUri: "local://reference_diagnostic_test",
    thumbnailUri: "memory://reference_diagnostic_test/thumbnail",
    analysisStatus: "ready",
    extractedFeatures: {
      framing: "portrait",
      apparentFocalLength: "telephoto",
      cameraHeight: "eye_level",
      subjectScale: 0.6,
      poseHints: ["relaxed_shoulders"],
      lightingDirection: "front_soft",
      colorMood: "warm",
      depthStyle: "shallow",
      achievableTranslationNotes: ["Match light and framing on this phone."],
    },
    display: {
      showCameraPopup,
      popupPosition: "top_right",
      viewerState: "collapsed_popup",
    },
    privacy: {
      cloudAnalysisUsed,
      userConsentedToCloudAnalysis: cloudAnalysisUsed,
    },
  };
}

function captureCoachingSummaryFixture() {
  return {
    headline: "Good direction",
    bestShotScore: 0.82,
    targetMatch: 0.8,
    positiveSignals: [{
      id: "pose",
      title: "Pose",
      value: 0.86,
      reason: "improve_pose",
    }],
    improvementSignals: [{
      id: "lighting",
      title: "Lighting",
      value: 0.68,
      reason: "improve_face_light",
    }],
    topCorrectionReason: "improve_face_light",
    nextShotInstruction: "Next shot: turn toward cleaner light",
    privacy: {
      singlePhoneOnly: true,
      storesRawPhoto: false,
      uploadsLiveCameraFrame: false,
      identityRecognitionAllowed: false,
    },
  };
}

function calibrationReadinessReportFixture(isReady) {
  return {
    status: isReady ? "ready" : "needs_more_samples",
    reviewedSampleCount: isReady ? 24 : 1,
    targetRealCaptureCount: 24,
    missingSampleCount: isReady ? 0 : 23,
    reviewedDomains: isReady ? ["landscape", "lifestyle", "night", "portrait"] : ["portrait"],
    missingDomains: isReady ? [] : ["landscape", "lifestyle", "night"],
    scenarioTargetCount: 3,
    scenarioCounts: {
      portrait: isReady ? 3 : 1,
      landscape: isReady ? 3 : 0,
      sky: isReady ? 3 : 0,
      clutter: isReady ? 3 : 0,
      backlight: isReady ? 3 : 0,
      horizon: isReady ? 3 : 0,
      motion: isReady ? 3 : 0,
      night: isReady ? 3 : 0,
    },
    missingScenarios: isReady ? [] : ["portrait", "landscape", "sky", "clutter", "backlight", "horizon", "motion", "night"],
    isReadyForProductionCalibration: isReady,
  };
}

function aggregateSinglePhoneAiDiagnosticsStatus(checks) {
  if (checks.some((check) => check.status === "blocked")) return "blocked";
  if (checks.some((check) => check.status === "attention")) return "attention";
  return "passed";
}

function referencePopupDiagnosticCheck(referencePhoto) {
  if (!referencePhoto) {
    return {
      id: "reference_popup",
      title: "Reference Popup",
      status: "attention",
      detail: "No reference active",
    };
  }

  if (referencePhoto.privacy.cloudAnalysisUsed) {
    return {
      id: "reference_popup",
      title: "Reference Popup",
      status: "blocked",
      detail: "Cloud analysis detected",
    };
  }

  return {
    id: "reference_popup",
    title: "Reference Popup",
    status: referencePhoto.display.showCameraPopup ? "passed" : "attention",
    detail: referencePhoto.display.showCameraPopup ? "Popup visible" : "Popup hidden",
  };
}

function onlineReferencePlanDiagnosticCheck(plan) {
  if (!plan) {
    return {
      id: "online_reference_plan",
      title: "Online Plan",
      status: "attention",
      detail: "Not enabled",
    };
  }

  const isSafe = plan.privacy.singlePhoneOnly &&
    plan.privacy.requiresUserConsent &&
    !plan.privacy.sendsRawCameraFrame &&
    !plan.privacy.sendsPrivatePhoto &&
    !plan.privacy.sendsIdentityData;

  return {
    id: "online_reference_plan",
    title: "Online Plan",
    status: isSafe ? "passed" : "blocked",
    detail: `${plan.searchQueries.length} public queries`,
  };
}

function onlineProviderHealthDiagnosticCheck(snapshot) {
  if (!snapshot) {
    return {
      id: "online_provider_health",
      title: "Source Health",
      status: "attention",
      detail: "Not checked",
    };
  }

  const isSafe = snapshot.privacy.singlePhoneOnly &&
    !snapshot.privacy.sendsRawCameraFrame &&
    !snapshot.privacy.sendsPrivatePhoto &&
    !snapshot.privacy.sendsIdentityData &&
    !snapshot.privacy.sendsPreciseLocation;

  if (!isSafe) {
    return {
      id: "online_provider_health",
      title: "Source Health",
      status: "blocked",
      detail: "Unsafe provider payload",
    };
  }

  switch (snapshot.status) {
    case "available":
      return {
        id: "online_provider_health",
        title: "Source Health",
        status: "passed",
        detail: `${snapshot.totalResultCount} public references`,
      };
    case "degraded":
      return {
        id: "online_provider_health",
        title: "Source Health",
        status: "attention",
        detail: "Partial results",
      };
    case "empty":
      return {
        id: "online_provider_health",
        title: "Source Health",
        status: "attention",
        detail: "No matches",
      };
    case "failed":
      return {
        id: "online_provider_health",
        title: "Source Health",
        status: "attention",
        detail: "Unavailable",
      };
    default:
      return {
        id: "online_provider_health",
        title: "Source Health",
        status: "attention",
        detail: "Unknown",
      };
  }
}

function localLearningDiagnosticCheck(profile) {
  if (!profile.consent.learningEnabled) {
    return {
      id: "local_learning",
      title: "Local Learning",
      status: "attention",
      detail: "Off",
    };
  }

  return {
    id: "local_learning",
    title: "Local Learning",
    status: profile.totalEvents > 0 ? "passed" : "attention",
    detail: `${profile.totalEvents} events`,
  };
}

function calibrationReadinessDiagnosticCheck(report) {
  if (!report) {
    return {
      id: "calibration_readiness",
      title: "Calibration Data",
      status: "attention",
      detail: "Manifest unavailable",
    };
  }

  if (report.isReadyForProductionCalibration) {
    return {
      id: "calibration_readiness",
      title: "Calibration Data",
      status: "passed",
      detail: `${report.reviewedSampleCount}/${report.targetRealCaptureCount} captures`,
    };
  }

  const detail = report.missingSampleCount > 0
    ? `Need ${report.missingSampleCount} captures`
    : report.missingScenarios.length > 0
      ? `Missing ${report.missingScenarios.length} scenarios`
      : `Missing ${report.missingDomains.length} domains`;

  return {
    id: "calibration_readiness",
    title: "Calibration Data",
    status: "attention",
    detail,
  };
}

function learningStoreDiagnosticCheck(profile, protection) {
  if (!profile.consent.learningEnabled) {
    return {
      id: "learning_store",
      title: "Learning Store",
      status: "attention",
      detail: "Learning off",
    };
  }

  const encryptedAtRest = protection === "keychain_encrypted_this_device_only";

  return {
    id: "learning_store",
    title: "Learning Store",
    status: encryptedAtRest ? "passed" : "attention",
    detail: encryptedAtRest ? "Keychain encrypted" : "Local file fallback",
  };
}

function captureCoachingDiagnosticCheck(summary) {
  if (!summary) {
    return {
      id: "capture_coaching",
      title: "Capture Coaching",
      status: "attention",
      detail: "Not run",
    };
  }

  const isSafe = summary.privacy.singlePhoneOnly &&
    !summary.privacy.storesRawPhoto &&
    !summary.privacy.uploadsLiveCameraFrame &&
    !summary.privacy.identityRecognitionAllowed;

  return {
    id: "capture_coaching",
    title: "Capture Coaching",
    status: isSafe ? "passed" : "blocked",
    detail: summary.headline,
  };
}

function buildWikimediaCommonsSearchUrl(query, limit = 4, apiUrl = "https://commons.wikimedia.org/w/api.php") {
  const url = new URL(apiUrl);
  url.searchParams.set("action", "query");
  url.searchParams.set("generator", "search");
  url.searchParams.set("gsrsearch", query);
  url.searchParams.set("gsrnamespace", "6");
  url.searchParams.set("gsrlimit", String(Math.min(10, Math.max(1, limit))));
  url.searchParams.set("prop", "imageinfo");
  url.searchParams.set("iiprop", "url|mime|extmetadata");
  url.searchParams.set("iiurlwidth", "640");
  url.searchParams.set("format", "json");
  url.searchParams.set("formatversion", "2");
  url.searchParams.set("origin", "*");
  return url.toString();
}

function buildOpenverseSearchUrl(query, limit = 4, apiUrl = "https://api.openverse.engineering/v1/images/") {
  const url = new URL(apiUrl);
  url.searchParams.set("q", query);
  url.searchParams.set("page_size", String(Math.min(10, Math.max(1, limit))));
  url.searchParams.set("mature", "false");
  return url.toString();
}

function parseWikimediaCommonsSearchResponse(payload, query) {
  const pages = isRecord(payload) && isRecord(payload.query) && Array.isArray(payload.query.pages)
    ? payload.query.pages
    : [];

  return pages
    .slice()
    .sort((a, b) => pageIndex(a) - pageIndex(b))
    .flatMap((page) => {
      if (!isRecord(page) || typeof page.pageid !== "number" || typeof page.title !== "string") return [];
      const imageInfo = Array.isArray(page.imageinfo) && isRecord(page.imageinfo[0]) ? page.imageinfo[0] : undefined;
      if (!imageInfo || typeof imageInfo.descriptionurl !== "string") return [];
      if (typeof imageInfo.mime !== "string" || !imageInfo.mime.startsWith("image/")) return [];
      const imageUrl = typeof imageInfo.url === "string" ? imageInfo.url : undefined;
      const thumbnailUrl = typeof imageInfo.thumburl === "string" ? imageInfo.thumburl : undefined;
      if (!imageUrl && !thumbnailUrl) return [];

      const extmetadata = isRecord(imageInfo.extmetadata) ? imageInfo.extmetadata : {};
      return [{
        id: `wikimedia_commons_${page.pageid}`,
        source: "wikimedia_commons",
        query,
        title: page.title.startsWith("File:") ? page.title.slice("File:".length) : page.title,
        pageUrl: imageInfo.descriptionurl,
        thumbnailUrl,
        imageUrl,
        mimeType: imageInfo.mime,
        license: metadataValue(extmetadata.LicenseShortName),
        creator: metadataValue(extmetadata.Artist),
        privacy: {
          publicSourceOnly: true,
          derivedFromPromptOnly: true,
          storesRawPhoto: false,
          uploadsLiveCameraFrame: false,
          identityRecognitionAllowed: false,
        },
      }];
    });
}

function parseOpenverseSearchResponse(payload, query) {
  const results = isRecord(payload) && Array.isArray(payload.results)
    ? payload.results
    : [];

  return results.flatMap((item) => {
    if (!isRecord(item) || item.mature === true || typeof item.id !== "string" || !item.id.trim()) return [];
    const imageUrl = typeof item.url === "string" ? item.url : undefined;
    const thumbnailUrl = typeof item.thumbnail === "string" ? item.thumbnail : undefined;
    if (!imageUrl && !thumbnailUrl) return [];

    const pageUrl = typeof item.foreign_landing_url === "string"
      ? item.foreign_landing_url
      : typeof item.frontend_url === "string"
        ? item.frontend_url
        : imageUrl;
    if (!pageUrl) return [];

    return [{
      id: `openverse_${item.id.trim()}`,
      source: "openverse",
      query,
      title: cleanText(typeof item.title === "string" ? item.title : "") || "Openverse public reference",
      pageUrl,
      thumbnailUrl,
      imageUrl,
      mimeType: inferredMimeType(imageUrl ?? thumbnailUrl),
      license: openverseLicenseLabel(
        typeof item.license === "string" ? item.license : undefined,
        typeof item.license_version === "string" ? item.license_version : undefined
      ),
      creator: typeof item.creator === "string" ? cleanText(item.creator) || undefined : undefined,
      privacy: {
        publicSourceOnly: true,
        derivedFromPromptOnly: true,
        storesRawPhoto: false,
        uploadsLiveCameraFrame: false,
        identityRecognitionAllowed: false,
      },
    }];
  });
}

function rankOnlineInspirationResults(results, request) {
  const queryOrder = new Map(request.queries.map((query, index) => [query.toLowerCase(), index]));
  const queryTokens = new Set(request.queries.flatMap(tokenizeForRanking));

  const ranked = results
    .map((result, index) => ({
      result,
      index,
      score: scoreOnlineInspirationResult(result, index, queryOrder, queryTokens),
    }))
    .sort((a, b) => b.score - a.score || a.index - b.index);

  return diversifyScoredResults(ranked).map(({ result }) => result);
}

function makeThumbnailMemoryCache(maxEntries = 24) {
  const entries = new Map();
  return {
    get(url) {
      return entries.get(url);
    },
    set(url, data) {
      entries.delete(url);
      entries.set(url, data);
      while (entries.size > Math.max(1, maxEntries)) {
        const oldest = entries.keys().next().value;
        if (!oldest) break;
        entries.delete(oldest);
      }
    },
    clear() {
      entries.clear();
    },
  };
}

function canLearnLocally(event) {
  return event.privacy.singlePhoneOnly &&
    !event.privacy.storesRawPhoto &&
    !event.privacy.uploadsLiveCameraFrame &&
    !event.privacy.identityRecognitionAllowed;
}

function outcomeSignal(event) {
  let signal;
  switch (event.outcome) {
    case "accepted_guidance":
    case "selected_best_shot":
    case "saved_result":
      signal = 0.7;
      break;
    case "shared_result":
      signal = 0.9;
      break;
    case "edited_after_capture":
      signal = 0.2;
      break;
    case "rejected_guidance":
      signal = -0.5;
      break;
    case "deleted_result":
      signal = -0.8;
      break;
    default:
      signal = 0;
  }

  if (typeof event.userRating === "number") signal += (Math.min(5, Math.max(1, event.userRating)) - 3) / 4;
  if (typeof event.selectedTargetMatch === "number") signal += (Math.min(1, Math.max(0, event.selectedTargetMatch)) - 0.75) * 0.6;
  return Math.min(1, Math.max(-1, signal));
}

function bump(values, key, amount) {
  if (!key || !Number.isFinite(amount)) return;
  values[key] = Number.isFinite(values[key] ?? 0) ? Math.min(1, Math.max(-1, (values[key] ?? 0) + amount)) : 0;
}

function sanitizeCountMap(values, allowedKeys, maxEntries) {
  const allowed = new Set(allowedKeys);
  return Object.fromEntries(
    Object.entries(values ?? {})
      .map(([key, value]) => [sanitizeStorageKey(key), clampCount(value)])
      .filter(([key, value]) => allowed.has(key) && value > 0)
      .sort(([leftKey, leftValue], [rightKey, rightValue]) => rightValue - leftValue || leftKey.localeCompare(rightKey))
      .slice(0, Math.max(0, maxEntries))
  );
}

function sanitizeAffinityMap(values, allowedKeys, maxEntries) {
  const allowed = allowedKeys ? new Set(allowedKeys) : undefined;
  return Object.fromEntries(
    Object.entries(values ?? {})
      .map(([key, value]) => [sanitizeStorageKey(key), clampAffinity(value)])
      .filter(([key, value]) => key.length > 0 && value !== 0 && (!allowed || allowed.has(key)) && (allowed || !isBlockedFreeformStorageKey(key)))
      .sort(([leftKey, leftValue], [rightKey, rightValue]) => Math.abs(rightValue) - Math.abs(leftValue) || leftKey.localeCompare(rightKey))
      .slice(0, Math.max(0, maxEntries))
  );
}

function clampCount(value) {
  if (!Number.isFinite(value ?? 0)) return 0;
  return Math.min(1_000_000, Math.max(0, Math.trunc(value ?? 0)));
}

function clampAffinity(value) {
  if (!Number.isFinite(value ?? 0)) return 0;
  return Math.min(1, Math.max(-1, value ?? 0));
}

function sanitizeStorageKey(value) {
  return value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, "_")
    .replace(/^[_-]+|[_-]+$/g, "")
    .slice(0, 64)
    .replace(/^[_-]+|[_-]+$/g, "");
}

function isBlockedFreeformStorageKey(value) {
  return [
    "raw_live_camera",
    "raw_frame",
    "private_photo",
    "face_identity",
    "identity_recognition",
    "upload_live_camera",
    "upload_private",
    "external_cloud",
  ].some((term) => value.includes(term));
}

function containsAny(text, terms) {
  return terms.some((term) => text.includes(term));
}

function compactPromptQuery(prompt) {
  return prompt
    .split(/[^a-z0-9]+/i)
    .filter(Boolean)
    .slice(0, 10)
    .join(" ");
}

function uniqueNonEmpty(values) {
  return [...new Set(values.map((value) => value.trim()).filter(Boolean))];
}

function isCreativeInterpretationPrivacySafe(privacy) {
  return privacy.singlePhoneOnly &&
    privacy.requiresUserConsent &&
    !privacy.sendsRawCameraFrame &&
    !privacy.sendsPrivatePhoto &&
    !privacy.sendsIdentityData &&
    !privacy.sendsPreciseLocation &&
    !privacy.sendsRawLearningEvents &&
    !privacy.allowsGenerativeOutput;
}

function blockedCreativeInterpretationPayloadTerms(plan) {
  const inspectedText = [
    ...plan.inputSummary,
    ...plan.suggestions.flatMap((suggestion) => [suggestion.title, suggestion.instruction]),
  ].join(" ").toLowerCase();

  return creativeInterpretationBlockedPayloadTerms.filter((term) => inspectedText.includes(term));
}

function creativeInterpretationGuidanceFromRequest(request) {
  let remainingWords = request.maxResponseWords;
  const guidance = [];
  const safetyBrief = request.suggestionBriefs.find((brief) => brief.toLowerCase().includes("capture-realistic"));
  const briefs = safetyBrief
    ? [
      ...request.suggestionBriefs.filter((brief) => brief !== safetyBrief).slice(0, 3),
      safetyBrief,
    ]
    : request.suggestionBriefs.slice(0, 4);

  for (const brief of briefs) {
    if (remainingWords <= 0) break;

    const words = brief.trim().split(/\s+/).filter(Boolean);
    if (words.length === 0) continue;

    const selectedWords = words.slice(0, remainingWords);
    const item = selectedWords.join(" ");
    if (item) {
      guidance.push(item);
    }
    remainingWords -= selectedWords.length;
  }

  return guidance;
}

function makeOpenAICreativeInterpretationResponsesPayload(request, options = {}) {
  if (!request.payloadAudit.safeToSend || !isCreativeInterpretationPrivacySafe(request.privacy)) {
    throw new Error("unsafe_openai_creative_interpretation_request");
  }

  const payload = {
    model: options.model?.trim() || openAICreativeInterpretationDefaults.model,
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
      lenspilot_plan_id: request.planId.slice(0, 64),
      lenspilot_provider: request.provider,
      lenspilot_payload: "audited_text_only",
    },
  };

  if (options.allowsWebSearch ?? true) {
    payload.tools = [{ type: "web_search" }];
    payload.tool_choice = "auto";
    payload.max_tool_calls = Math.min(4, Math.max(1, Math.trunc(options.maxToolCalls ?? openAICreativeInterpretationDefaults.maxToolCalls)));
  }

  return payload;
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

function parseOpenAICreativeInterpretationProviderResult(payload) {
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

function cleanProviderText(value, maxLength) {
  const collapsed = value
    .split(/\s+/)
    .join(" ")
    .trim();
  return collapsed.length <= maxLength ? collapsed : collapsed.slice(0, maxLength).trim();
}

function isRecord(value) {
  return typeof value === "object" && value !== null;
}

function pageIndex(value) {
  return isRecord(value) && typeof value.index === "number" ? value.index : Number.MAX_SAFE_INTEGER;
}

function metadataValue(value) {
  if (!isRecord(value) || typeof value.value !== "string") return undefined;
  const cleaned = cleanText(value.value);
  return cleaned || undefined;
}

function cleanText(value) {
  return value
    .replace(/<[^>]+>/g, "")
    .replace(/&quot;/g, "\"")
    .replace(/&amp;/g, "&")
    .trim();
}

function openverseLicenseLabel(license, version) {
  const cleanedLicense = license?.trim();
  if (!cleanedLicense) return undefined;

  const normalized = cleanedLicense.toLowerCase();
  if (normalized === "pdm") return "Public Domain Mark";
  if (normalized === "cc0") return "CC0";

  const cleanedVersion = version?.trim();
  return cleanedVersion ? `CC ${cleanedLicense.toUpperCase()} ${cleanedVersion}` : `CC ${cleanedLicense.toUpperCase()}`;
}

function inferredMimeType(url) {
  if (!url) return undefined;
  const pathname = new URL(url, "https://lenspilot.local").pathname.toLowerCase();
  if (pathname.endsWith(".jpg") || pathname.endsWith(".jpeg")) return "image/jpeg";
  if (pathname.endsWith(".png")) return "image/png";
  if (pathname.endsWith(".webp")) return "image/webp";
  if (pathname.endsWith(".gif")) return "image/gif";
  return undefined;
}

function diversifyScoredResults(ranked) {
  const selectedIds = new Set();
  const selectedSources = new Set();
  const diversified = [];

  for (const item of ranked) {
    if (selectedSources.has(item.result.source)) continue;
    selectedSources.add(item.result.source);
    selectedIds.add(item.result.id);
    diversified.push(item);
  }

  for (const item of ranked) {
    if (selectedIds.has(item.result.id)) continue;
    selectedIds.add(item.result.id);
    diversified.push(item);
  }

  return diversified;
}

function scoreOnlineInspirationResult(result, originalIndex, queryOrder, queryTokens) {
  const resultTokens = new Set(tokenizeForRanking(`${result.title} ${result.query}`));
  const overlap = queryTokens.size === 0
    ? 0
    : [...resultTokens].filter((token) => queryTokens.has(token)).length / queryTokens.size;
  const queryPosition = queryOrder.has(result.query.toLowerCase())
    ? Math.max(0, 1 - (queryOrder.get(result.query.toLowerCase()) ?? 0) * 0.18)
    : 0;
  const title = result.title.toLowerCase();
  const mimeType = result.mimeType?.toLowerCase() ?? "";

  let score = queryPosition + overlap * 1.4 - originalIndex * 0.001;
  if (result.thumbnailUrl) score += 0.35;
  if (result.imageUrl) score += 0.2;
  if (result.license) score += 0.12;
  if (result.creator) score += 0.08;
  if (["image/jpeg", "image/png", "image/webp"].includes(mimeType)) score += 0.25;
  if (mimeType === "image/svg+xml") score -= 0.45;
  if (containsAny(title, ["portrait", "photo", "photograph", "camera", "street", "landscape", "travel", "cinematic"])) score += 0.2;
  if (containsAny(title, ["logo", "icon", "diagram", "map", "flag", "seal", "coat of arms"])) score -= 0.35;
  return score;
}

function tokenizeForRanking(value) {
  return value
    .toLowerCase()
    .split(/[^a-z0-9]+/i)
    .filter((token) => token.length > 2);
}

function assert(condition, message) {
  if (!condition) {
    console.error(message);
    process.exit(1);
  }
}

function assertThrows(callback, message) {
  let didThrow = false;
  try {
    callback();
  } catch {
    didThrow = true;
  }

  assert(didThrow, message);
}
