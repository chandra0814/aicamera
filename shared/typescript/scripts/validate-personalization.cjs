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

const shotSpec = {
  id: "shot_personalization_fixture",
  domain: "portrait",
  style: { name: "cinematic", colorIntent: "warm_highlights_cool_shadows" },
  composition: { framing: "environmental", backgroundPriority: "clean" },
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

console.log(JSON.stringify({
  personalLearning: true,
  onlineReferencePlan: plan.reason,
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

function assert(condition, message) {
  if (!condition) {
    console.error(message);
    process.exit(1);
  }
}
