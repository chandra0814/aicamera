import type { CaptureDomain, ReferencePhotoState, ShotSpec } from "./contracts";
import type { GuidanceAction } from "./planning";
import { defaultGuidanceCalibration, type CaptureCoachingSummary, type GuidanceCalibration, type TargetMatchCalibrationReadinessReport } from "./ai-core";

export interface PersonalizationConsent {
  learningEnabled: boolean;
  onlineReferencesAllowed: boolean;
  cloudPersonalizationSyncAllowed: boolean;
}

export const disabledPersonalizationConsent: PersonalizationConsent = {
  learningEnabled: false,
  onlineReferencesAllowed: false,
  cloudPersonalizationSyncAllowed: false,
};

export const localLearningConsent: PersonalizationConsent = {
  learningEnabled: true,
  onlineReferencesAllowed: false,
  cloudPersonalizationSyncAllowed: false,
};

export interface PersonalLearningEvent {
  id: string;
  timestamp: string;
  domain: CaptureDomain;
  outcome:
    | "accepted_guidance"
    | "rejected_guidance"
    | "selected_best_shot"
    | "saved_result"
    | "shared_result"
    | "deleted_result"
    | "edited_after_capture";
  promptRequirements: string[];
  acceptedGuidanceReason?: GuidanceAction["reason"];
  rejectedGuidanceReason?: GuidanceAction["reason"];
  customerCorrectionReason?: GuidanceAction["reason"];
  selectedStyle?: ShotSpec["style"]["name"];
  selectedColorIntent?: ShotSpec["style"]["colorIntent"];
  selectedFraming?: ShotSpec["composition"]["framing"];
  selectedTargetMatch?: number;
  userRating?: number;
  onlineReferenceUsed: boolean;
  privacy: {
    singlePhoneOnly: boolean;
    storesRawPhoto: boolean;
    uploadsLiveCameraFrame: boolean;
    identityRecognitionAllowed: boolean;
  };
}

export interface PersonalVisualPreferenceProfile {
  version: "1.0";
  consent: PersonalizationConsent;
  totalEvents: number;
  domainCounts: Partial<Record<CaptureDomain, number>>;
  styleAffinities: Partial<Record<ShotSpec["style"]["name"], number>>;
  colorAffinities: Partial<Record<NonNullable<ShotSpec["style"]["colorIntent"]>, number>>;
  framingAffinities: Partial<Record<ShotSpec["composition"]["framing"], number>>;
  guidanceReasonAffinities: Partial<Record<GuidanceAction["reason"], number>>;
  requirementAffinities: Record<string, number>;
  onlineReferenceUsageCount: number;
}

export type PersonalVisualProfileStorageProtection =
  | "local_file"
  | "keychain_encrypted_this_device_only";

export interface OnlineReferencePlan {
  id: string;
  reason: "explicit_user_request" | "specialized_style" | "insufficient_personal_history";
  searchQueries: string[];
  allowedInputs: Array<"prompt_text" | "shot_spec_summary" | "device_capability_summary">;
  mustNotSend: string[];
  userDisclosure: string;
  privacy: {
    singlePhoneOnly: true;
    requiresUserConsent: true;
    sendsRawCameraFrame: false;
    sendsPrivatePhoto: false;
    sendsIdentityData: false;
  };
}

export interface CreativeInterpretationPlan {
  id: string;
  reason: "explicit_user_request" | "specialized_style" | "online_inspiration" | "learned_preference";
  inputSummary: string[];
  suggestions: Array<{
    id: string;
    category: "lighting" | "composition" | "lens" | "color" | "reference" | "safety";
    title: string;
    instruction: string;
  }>;
  allowedInputs: Array<
    | "prompt_text"
    | "shot_spec_summary"
    | "learned_preference_summary"
    | "public_reference_summary"
    | "device_capability_summary"
  >;
  mustNotSend: string[];
  userDisclosure: string;
  privacy: {
    singlePhoneOnly: true;
    requiresUserConsent: true;
    sendsRawCameraFrame: false;
    sendsPrivatePhoto: false;
    sendsIdentityData: false;
    sendsPreciseLocation: false;
    sendsRawLearningEvents: false;
    allowsGenerativeOutput: false;
  };
}

export type CreativeInterpretationDeniedReason =
  | "unsafe_privacy"
  | "missing_required_blocklist"
  | "empty_allowed_inputs"
  | "empty_safe_summary"
  | "empty_suggestions"
  | "blocked_term_detected";

export interface CreativeInterpretationPayloadAudit {
  safeToSend: boolean;
  deniedReasons: CreativeInterpretationDeniedReason[];
  blockedTermsDetected: string[];
  allowedInputCount: number;
  summaryCount: number;
  suggestionCount: number;
}

export type CreativeInterpretationProvider = "local_heuristic" | "online_reasoning";

export interface CreativeInterpretationRequest {
  planId: string;
  provider: CreativeInterpretationProvider;
  inputSummary: string[];
  suggestionBriefs: string[];
  allowedInputs: CreativeInterpretationPlan["allowedInputs"];
  maxResponseWords: number;
  payloadAudit: CreativeInterpretationPayloadAudit;
  privacy: CreativeInterpretationPlan["privacy"];
}

export type OnlineInspirationSource = "public_sources" | "wikimedia_commons" | "openverse";

export interface OnlineInspirationRequest {
  planId: string;
  queries: string[];
  perQueryLimit: number;
  source: OnlineInspirationSource;
  privacy: {
    singlePhoneOnly: true;
    requiresUserConsent: true;
    sendsRawCameraFrame: false;
    sendsPrivatePhoto: false;
    sendsIdentityData: false;
    sendsPreciseLocation: false;
  };
}

export interface OnlineInspirationResult {
  id: string;
  source: OnlineInspirationSource;
  query: string;
  title: string;
  pageUrl: string;
  thumbnailUrl?: string;
  imageUrl?: string;
  mimeType?: string;
  license?: string;
  creator?: string;
  privacy: {
    publicSourceOnly: true;
    derivedFromPromptOnly: true;
    storesRawPhoto: false;
    uploadsLiveCameraFrame: false;
    identityRecognitionAllowed: false;
  };
}

export type OnlineInspirationProviderHealthStatus = "available" | "empty" | "failed";
export type OnlineInspirationHealthStatus = "available" | "degraded" | "empty" | "failed";

export interface OnlineInspirationProviderHealth {
  source: OnlineInspirationSource;
  status: OnlineInspirationProviderHealthStatus;
  resultCount: number;
  checkedAt: string;
  message?: string;
  privacy: {
    publicSourceOnly: true;
    derivedFromPromptOnly: true;
    storesRawPhoto: false;
    uploadsLiveCameraFrame: false;
    sendsIdentityData: false;
    sendsPreciseLocation: false;
  };
}

export interface OnlineInspirationHealthSnapshot {
  planId: string;
  source: OnlineInspirationSource;
  status: OnlineInspirationHealthStatus;
  checkedAt: string;
  totalResultCount: number;
  providers: OnlineInspirationProviderHealth[];
  privacy: {
    singlePhoneOnly: true;
    requiresUserConsent: true;
    sendsRawCameraFrame: false;
    sendsPrivatePhoto: false;
    sendsIdentityData: false;
    sendsPreciseLocation: false;
  };
}

export type CreativeInterpretationProviderHealthGateDeniedReason =
  | "unsafe_request_payload"
  | "missing_provider_health"
  | "unsafe_provider_health"
  | "provider_unavailable"
  | "no_public_references";

export interface CreativeInterpretationProviderHealthGate {
  canRunProvider: boolean;
  deniedReasons: CreativeInterpretationProviderHealthGateDeniedReason[];
  providerHealthStatus?: OnlineInspirationHealthStatus;
  publicReferenceCount: number;
  payloadAudit: CreativeInterpretationPayloadAudit;
  privacy: {
    singlePhoneOnly: boolean;
    requiresUserConsent: boolean;
    sendsRawCameraFrame: boolean;
    sendsPrivatePhoto: boolean;
    sendsIdentityData: boolean;
    sendsPreciseLocation: boolean;
    sendsRawLearningEvents: boolean;
  };
}

export interface CreativeInterpretationResponse {
  id: string;
  planId: string;
  provider: CreativeInterpretationProvider;
  status: "completed";
  headline: string;
  guidance: string[];
  maxResponseWords: number;
  generatedAt: string;
  payloadAudit: CreativeInterpretationPayloadAudit;
  healthGate: CreativeInterpretationProviderHealthGate;
  privacy: {
    singlePhoneOnly: true;
    usesAuditedPayload: true;
    usesProviderHealthGate: true;
    storesRawPhoto: false;
    uploadsLiveCameraFrame: false;
    sendsPrivatePhoto: false;
    sendsIdentityData: false;
    sendsPreciseLocation: false;
    sendsRawLearningEvents: false;
    allowsGenerativeImageOutput: false;
  };
}

export interface CreativeInterpretationProviderResult {
  headline: string;
  guidance: string[];
}

export interface OpenAICreativeInterpretationOptions {
  model?: string;
  allowsWebSearch?: boolean;
  maxToolCalls?: number;
}

export interface OnlineInspirationResponse {
  planId: string;
  source: OnlineInspirationSource;
  sources: OnlineInspirationSource[];
  results: OnlineInspirationResult[];
  healthSnapshot: OnlineInspirationHealthSnapshot;
}

export type SinglePhoneAiDiagnosticsStatus = "passed" | "attention" | "blocked";

export interface SinglePhoneAiDiagnosticCheck {
  id: string;
  title: string;
  status: SinglePhoneAiDiagnosticsStatus;
  detail: string;
}

export interface SinglePhoneAiDiagnosticsReport {
  generatedAt: string;
  overallStatus: SinglePhoneAiDiagnosticsStatus;
  checks: SinglePhoneAiDiagnosticCheck[];
  privacy: {
    singlePhoneOnly: true;
    storesRawPhoto: false;
    uploadsLiveCameraFrame: false;
    sendsIdentityData: false;
    sendsPreciseLocation: false;
  };
}

export function emptyPersonalVisualPreferenceProfile(
  consent: PersonalizationConsent = disabledPersonalizationConsent
): PersonalVisualPreferenceProfile {
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

export const personalVisualProfileStoragePolicy = {
  storageKey: "com.lenspilot.personalVisualProfile.v1",
  preferredProtection: "keychain_encrypted_this_device_only" as const,
  legacyProtection: "local_file" as const,
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
} as const;

export interface PersonalVisualProfileStorageSnapshot {
  storageKey: string;
  storageProtection: PersonalVisualProfileStorageProtection;
  profile: PersonalVisualPreferenceProfile;
  estimatedJsonBytes: number;
  privacy: typeof personalVisualProfileStoragePolicy.privacy;
}

export function sanitizePersonalVisualPreferenceProfile(
  profile: PersonalVisualPreferenceProfile
): PersonalVisualPreferenceProfile {
  return {
    version: "1.0",
    consent: {
      learningEnabled: profile.consent.learningEnabled,
      onlineReferencesAllowed: profile.consent.onlineReferencesAllowed,
      cloudPersonalizationSyncAllowed: false,
    },
    totalEvents: clampCount(profile.totalEvents),
    domainCounts: sanitizeCountMap(profile.domainCounts, profileDomainKeys, profileDomainKeys.length) as Partial<Record<CaptureDomain, number>>,
    styleAffinities: sanitizeAffinityMap(profile.styleAffinities, profileStyleKeys, profileStyleKeys.length) as Partial<Record<ShotSpec["style"]["name"], number>>,
    colorAffinities: sanitizeAffinityMap(profile.colorAffinities, profileColorKeys, profileColorKeys.length) as Partial<Record<NonNullable<ShotSpec["style"]["colorIntent"]>, number>>,
    framingAffinities: sanitizeAffinityMap(profile.framingAffinities, profileFramingKeys, profileFramingKeys.length) as Partial<Record<ShotSpec["composition"]["framing"], number>>,
    guidanceReasonAffinities: sanitizeAffinityMap(profile.guidanceReasonAffinities, profileGuidanceReasonKeys, profileGuidanceReasonKeys.length) as Partial<Record<GuidanceAction["reason"], number>>,
    requirementAffinities: sanitizeAffinityMap(profile.requirementAffinities, undefined, 48),
    onlineReferenceUsageCount: clampCount(profile.onlineReferenceUsageCount),
  };
}

export function encodePersonalVisualPreferenceProfileForLocalStorage(
  profile: PersonalVisualPreferenceProfile
): string {
  const json = JSON.stringify(sanitizePersonalVisualPreferenceProfile(profile));
  if (json.length > personalVisualProfileStoragePolicy.maxStoredProfileBytes) {
    throw new Error("personal_visual_profile_too_large");
  }
  return json;
}

export function decodePersonalVisualPreferenceProfileFromLocalStorage(
  json: string
): PersonalVisualPreferenceProfile {
  if (json.length > personalVisualProfileStoragePolicy.maxStoredProfileBytes) {
    throw new Error("personal_visual_profile_too_large");
  }
  return sanitizePersonalVisualPreferenceProfile(JSON.parse(json) as PersonalVisualPreferenceProfile);
}

export function makePersonalVisualProfileStorageSnapshot(
  profile: PersonalVisualPreferenceProfile,
  storageKey = personalVisualProfileStoragePolicy.storageKey,
  storageProtection: PersonalVisualProfileStorageProtection = personalVisualProfileStoragePolicy.preferredProtection
): PersonalVisualProfileStorageSnapshot {
  const storedProfile = sanitizePersonalVisualPreferenceProfile(profile);
  return {
    storageKey,
    storageProtection,
    profile: storedProfile,
    estimatedJsonBytes: JSON.stringify(storedProfile).length,
    privacy: personalVisualProfileStoragePolicy.privacy,
  };
}

export class PersonalVisualLearningEngine {
  updatedProfile(
    profile: PersonalVisualPreferenceProfile,
    event: PersonalLearningEvent,
    consent: PersonalizationConsent = profile.consent
  ): PersonalVisualPreferenceProfile {
    if (!consent.learningEnabled || !canLearnLocally(event)) {
      return { ...profile, consent };
    }

    const signal = outcomeSignal(event);
    const next: PersonalVisualPreferenceProfile = {
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

    for (const requirement of event.promptRequirements) {
      bump(next.requirementAffinities, requirement, 0.04 * signal);
    }

    if (event.acceptedGuidanceReason) {
      bump(next.guidanceReasonAffinities, event.acceptedGuidanceReason, 0.08 * Math.max(0.25, signal));
    }

    if (event.rejectedGuidanceReason) {
      bump(next.guidanceReasonAffinities, event.rejectedGuidanceReason, -0.08 * Math.max(0.25, Math.abs(signal)));
    }

    if (event.customerCorrectionReason) {
      const correctionSignal = Math.max(0.4, Math.abs(signal));
      bump(next.guidanceReasonAffinities, event.customerCorrectionReason, 0.10 * correctionSignal);
      bump(next.requirementAffinities, `customer_correction_${event.customerCorrectionReason}`, 0.05 * correctionSignal);
    }

    return next;
  }

  guidanceCalibration(profile: PersonalVisualPreferenceProfile): GuidanceCalibration {
    if (!profile.consent.learningEnabled) return defaultGuidanceCalibration;

    return {
      globalReasonBoosts: Object.fromEntries(
        Object.entries(profile.guidanceReasonAffinities)
          .filter(([, affinity]) => (affinity ?? 0) > 0)
          .map(([reason, affinity]) => [reason, Math.min(0.04, (affinity ?? 0) * 0.04)])
      ) as GuidanceCalibration["globalReasonBoosts"],
      domainReasonBoosts: {},
    };
  }

  makeOnlineReferencePlan(
    shotSpec: ShotSpec,
    prompt: string,
    profile: PersonalVisualPreferenceProfile,
    consent: PersonalizationConsent = profile.consent
  ): OnlineReferencePlan | undefined {
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

  makeCreativeInterpretationPlan(
    shotSpec: ShotSpec,
    prompt: string,
    profile: PersonalVisualPreferenceProfile,
    onlineReferencePlan?: OnlineReferencePlan,
    consent: PersonalizationConsent = profile.consent
  ): CreativeInterpretationPlan | undefined {
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

    const allowedInputs: CreativeInterpretationPlan["allowedInputs"] = [
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
}

const profileDomainKeys = ["portrait", "landscape", "travel", "lifestyle", "night", "reference"] as const;
const profileStyleKeys = ["natural", "cinematic", "professional", "travel", "portrait", "night", "sky", "lifestyle", "custom"] as const;
const profileColorKeys = ["natural", "warm_highlights", "cool_shadows", "warm_highlights_cool_shadows", "high_contrast", "low_contrast"] as const;
const profileFramingKeys = ["close", "medium", "wide", "environmental", "three_quarter", "symmetrical", "rule_of_thirds"] as const;
const profileGuidanceReasonKeys = [
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
] as const;

function sanitizeCountMap(
  values: Partial<Record<string, number>>,
  allowedKeys: readonly string[],
  maxEntries: number
): Record<string, number> {
  const allowed = new Set(allowedKeys);
  return Object.fromEntries(
    Object.entries(values ?? {})
      .map(([key, value]) => [sanitizeStorageKey(key), clampCount(value)] as const)
      .filter(([key, value]) => allowed.has(key) && value > 0)
      .sort(([leftKey, leftValue], [rightKey, rightValue]) => rightValue - leftValue || leftKey.localeCompare(rightKey))
      .slice(0, Math.max(0, maxEntries))
  );
}

function sanitizeAffinityMap(
  values: Partial<Record<string, number>>,
  allowedKeys: readonly string[] | undefined,
  maxEntries: number
): Record<string, number> {
  const allowed = allowedKeys ? new Set(allowedKeys) : undefined;
  return Object.fromEntries(
    Object.entries(values ?? {})
      .map(([key, value]) => [sanitizeStorageKey(key), clampAffinity(value)] as const)
      .filter(([key, value]) => key.length > 0 && value !== 0 && (!allowed || allowed.has(key)) && (allowed || !isBlockedFreeformStorageKey(key)))
      .sort(([leftKey, leftValue], [rightKey, rightValue]) => Math.abs(rightValue) - Math.abs(leftValue) || leftKey.localeCompare(rightKey))
      .slice(0, Math.max(0, maxEntries))
  );
}

function clampCount(value: number | undefined): number {
  if (!Number.isFinite(value ?? 0)) return 0;
  return Math.min(1_000_000, Math.max(0, Math.trunc(value ?? 0)));
}

function sanitizeStorageKey(value: string): string {
  return value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, "_")
    .replace(/^[_-]+|[_-]+$/g, "")
    .slice(0, 64)
    .replace(/^[_-]+|[_-]+$/g, "");
}

function isBlockedFreeformStorageKey(value: string): boolean {
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

export function makeOnlineInspirationRequest(
  plan: OnlineReferencePlan,
  perQueryLimit = 4
): OnlineInspirationRequest {
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

export function makeCreativeInterpretationPayloadAudit(
  plan: CreativeInterpretationPlan
): CreativeInterpretationPayloadAudit {
  const blockedTermsDetected = blockedCreativeInterpretationPayloadTerms(plan);
  const deniedReasons: CreativeInterpretationDeniedReason[] = [];

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

export function makeCreativeInterpretationRequest(
  plan: CreativeInterpretationPlan,
  provider: CreativeInterpretationProvider = "online_reasoning",
  maxResponseWords = 120
): CreativeInterpretationRequest {
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

export const onlineInspirationProviderHealthPrivacy = {
  publicSourceOnly: true,
  derivedFromPromptOnly: true,
  storesRawPhoto: false,
  uploadsLiveCameraFrame: false,
  sendsIdentityData: false,
  sendsPreciseLocation: false,
} as const;

export const onlineInspirationHealthSnapshotPrivacy = {
  singlePhoneOnly: true,
  requiresUserConsent: true,
  sendsRawCameraFrame: false,
  sendsPrivatePhoto: false,
  sendsIdentityData: false,
  sendsPreciseLocation: false,
} as const;

export function makeOnlineInspirationProviderHealth(
  source: OnlineInspirationSource,
  resultCount: number,
  status?: OnlineInspirationProviderHealthStatus,
  checkedAt = new Date().toISOString(),
  message?: string
): OnlineInspirationProviderHealth {
  const safeResultCount = Number.isFinite(resultCount)
    ? Math.max(0, Math.floor(resultCount))
    : 0;
  const cleanedMessage = message?.trim();

  return {
    source,
    status: status ?? (safeResultCount > 0 ? "available" : "empty"),
    resultCount: safeResultCount,
    checkedAt,
    ...(cleanedMessage ? { message: cleanedMessage } : {}),
    privacy: onlineInspirationProviderHealthPrivacy,
  };
}

export function makeOnlineInspirationHealthSnapshot({
  planId,
  source,
  providers,
  checkedAt = new Date().toISOString(),
}: {
  planId: string;
  source: OnlineInspirationSource;
  providers: OnlineInspirationProviderHealth[];
  checkedAt?: string;
}): OnlineInspirationHealthSnapshot {
  return {
    planId,
    source,
    status: aggregateOnlineInspirationHealthStatus(providers),
    checkedAt,
    totalResultCount: providers.reduce((total, provider) => total + provider.resultCount, 0),
    providers,
    privacy: onlineInspirationHealthSnapshotPrivacy,
  };
}

export function aggregateOnlineInspirationHealthStatus(
  providers: OnlineInspirationProviderHealth[]
): OnlineInspirationHealthStatus {
  if (providers.length === 0) return "empty";

  const hasAvailableProvider = providers.some((provider) => provider.status === "available");
  const hasFailedProvider = providers.some((provider) => provider.status === "failed");

  if (hasAvailableProvider && hasFailedProvider) return "degraded";
  if (hasAvailableProvider) return "available";
  if (hasFailedProvider) return "failed";
  return "empty";
}

export const creativeInterpretationResponsePrivacy = {
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
} as const;

export const openAICreativeInterpretationDefaults = {
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
} as const;

export function makeCreativeInterpretationProviderHealthGate(
  request: CreativeInterpretationRequest,
  healthSnapshot?: OnlineInspirationHealthSnapshot
): CreativeInterpretationProviderHealthGate {
  const deniedReasons: CreativeInterpretationProviderHealthGateDeniedReason[] = [];
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
    const uniqueDeniedReasons = [...new Set(deniedReasons)].sort() as CreativeInterpretationProviderHealthGateDeniedReason[];
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
  const hasSafeProviderPrivacy = healthSnapshot.providers.every(
    (provider) =>
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

  const uniqueDeniedReasons = [...new Set(deniedReasons)].sort() as CreativeInterpretationProviderHealthGateDeniedReason[];

  return {
    canRunProvider: uniqueDeniedReasons.length === 0,
    deniedReasons: uniqueDeniedReasons,
    providerHealthStatus: healthSnapshot.status,
    publicReferenceCount: Math.max(0, healthSnapshot.totalResultCount),
    payloadAudit: request.payloadAudit,
    privacy,
  };
}

export function makeHealthGatedCreativeInterpretationResponse(
  plan: CreativeInterpretationPlan,
  healthSnapshot?: OnlineInspirationHealthSnapshot,
  provider: CreativeInterpretationProvider = "online_reasoning",
  maxResponseWords = 120,
  generatedAt = new Date().toISOString()
): CreativeInterpretationResponse {
  const request = makeCreativeInterpretationRequest(plan, provider, maxResponseWords);
  const healthGate = makeCreativeInterpretationProviderHealthGate(request, healthSnapshot);

  if (!healthGate.canRunProvider) {
    throw new Error(`creative_interpretation_health_gate_blocked:${healthGate.deniedReasons.join(",")}`);
  }

  const guidance = creativeInterpretationGuidanceFromRequest(request);
  if (guidance.length === 0) {
    throw new Error("empty_creative_interpretation_provider_output");
  }
  if (!isCreativeInterpretationProviderResultSafe({ headline: provider === "online_reasoning" ? "Provider-Ready Creative Brief" : "Local Creative Brief", guidance })) {
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
    privacy: creativeInterpretationResponsePrivacy,
  };
}

export function makeOpenAICreativeInterpretationResponsesPayload(
  request: CreativeInterpretationRequest,
  options: OpenAICreativeInterpretationOptions = {}
): Record<string, unknown> {
  if (!request.payloadAudit.safeToSend || !isCreativeInterpretationPrivacySafe(request.privacy)) {
    throw new Error("unsafe_openai_creative_interpretation_request");
  }

  const model = options.model?.trim() || openAICreativeInterpretationDefaults.model;
  const payload: Record<string, unknown> = {
    model,
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

export function parseOpenAICreativeInterpretationProviderResult(
  payload: unknown
): CreativeInterpretationProviderResult {
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

  let parsed: unknown;
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
    parsed.guidance.filter((item): item is string => typeof item === "string")
  );
  if (!isCreativeInterpretationProviderResultSafe(result)) {
    throw new Error("unsafe_creative_interpretation_provider_output");
  }

  return result;
}

export function makeCreativeInterpretationProviderResult(
  headline: string,
  guidance: string[]
): CreativeInterpretationProviderResult {
  return {
    headline: cleanProviderText(headline, 96),
    guidance: guidance
      .map((item) => cleanProviderText(item, 180))
      .filter(Boolean)
      .slice(0, 4),
  };
}

export function isCreativeInterpretationProviderResultSafe(
  result: CreativeInterpretationProviderResult
): boolean {
  const inspectedText = [result.headline, ...result.guidance].join(" ").toLowerCase();
  return !unsafeCreativeInterpretationProviderOutputTerms.some((term) => inspectedText.includes(term));
}

export const singlePhoneAiDiagnosticsPrivacy = {
  singlePhoneOnly: true,
  storesRawPhoto: false,
  uploadsLiveCameraFrame: false,
  sendsIdentityData: false,
  sendsPreciseLocation: false,
} as const;

export function makeSinglePhoneAiDiagnosticsReport({
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
}: {
  hasShotPlan: boolean;
  referencePhoto?: ReferencePhotoState;
  onlineReferencePlan?: OnlineReferencePlan;
  creativeInterpretationPlan?: CreativeInterpretationPlan;
  onlineInspirationHealthSnapshot?: OnlineInspirationHealthSnapshot;
  calibrationReadinessReport?: TargetMatchCalibrationReadinessReport;
  personalProfile: PersonalVisualPreferenceProfile;
  personalProfileStoreProtection?: PersonalVisualProfileStorageProtection;
  captureCoachingSummary?: CaptureCoachingSummary;
  generatedAt?: string;
}): SinglePhoneAiDiagnosticsReport {
  const checks: SinglePhoneAiDiagnosticCheck[] = [
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
    privacy: singlePhoneAiDiagnosticsPrivacy,
  };
}

function creativeInterpretationDiagnosticCheck(
  plan?: CreativeInterpretationPlan
): SinglePhoneAiDiagnosticCheck {
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

export function buildWikimediaCommonsSearchUrl(
  query: string,
  limit = 4,
  apiUrl = "https://commons.wikimedia.org/w/api.php"
): string {
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

export function buildOpenverseSearchUrl(
  query: string,
  limit = 4,
  apiUrl = "https://api.openverse.engineering/v1/images/"
): string {
  const url = new URL(apiUrl);
  url.searchParams.set("q", query);
  url.searchParams.set("page_size", String(Math.min(10, Math.max(1, limit))));
  url.searchParams.set("mature", "false");
  return url.toString();
}

export function parseWikimediaCommonsSearchResponse(
  payload: unknown,
  query: string
): OnlineInspirationResult[] {
  const pages = isRecord(payload) && isRecord(payload.query) && Array.isArray(payload.query.pages)
    ? payload.query.pages
    : [];

  return pages
    .slice()
    .sort((a, b) => pageIndex(a) - pageIndex(b))
    .flatMap((page): OnlineInspirationResult[] => {
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

export function parseOpenverseSearchResponse(
  payload: unknown,
  query: string
): OnlineInspirationResult[] {
  const results = isRecord(payload) && Array.isArray(payload.results)
    ? payload.results
    : [];

  return results.flatMap((item): OnlineInspirationResult[] => {
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

export async function fetchWikimediaCommonsReferences(
  request: OnlineInspirationRequest,
  fetcher: (url: string) => Promise<{ ok: boolean; status: number; json: () => Promise<unknown> }>
): Promise<OnlineInspirationResponse> {
  if (!request.privacy.singlePhoneOnly || request.privacy.sendsRawCameraFrame || request.privacy.sendsPrivatePhoto || request.privacy.sendsIdentityData) {
    throw new Error("unsafe_online_inspiration_request");
  }

  const seenPageUrls = new Set<string>();
  const results: OnlineInspirationResult[] = [];

  for (const query of request.queries.slice(0, 3)) {
    const response = await fetcher(buildWikimediaCommonsSearchUrl(query, request.perQueryLimit));
    if (!response.ok) throw new Error(`wikimedia_commons_http_${response.status}`);
    for (const result of parseWikimediaCommonsSearchResponse(await response.json(), query)) {
      if (seenPageUrls.has(result.pageUrl)) continue;
      seenPageUrls.add(result.pageUrl);
      results.push(result);
    }
  }

  const ranked = rankOnlineInspirationResults(results, request);
  return {
    planId: request.planId,
    source: request.source,
    sources: uniqueSources(ranked, request.source),
    results: ranked,
    healthSnapshot: makeOnlineInspirationHealthSnapshot({
      planId: request.planId,
      source: request.source,
      providers: [
        makeOnlineInspirationProviderHealth("wikimedia_commons", ranked.length),
      ],
    }),
  };
}

export function rankOnlineInspirationResults(
  results: OnlineInspirationResult[],
  request: OnlineInspirationRequest
): OnlineInspirationResult[] {
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

export class OnlineInspirationThumbnailMemoryCache {
  private entries = new Map<string, Uint8Array>();

  constructor(private readonly maxEntries = 24) {}

  get(url: string): Uint8Array | undefined {
    return this.entries.get(url);
  }

  set(url: string, data: Uint8Array): void {
    this.entries.delete(url);
    this.entries.set(url, data);
    while (this.entries.size > Math.max(1, this.maxEntries)) {
      const oldest = this.entries.keys().next().value;
      if (!oldest) break;
      this.entries.delete(oldest);
    }
  }

  async getOrFetch(
    url: string,
    fetcher: (url: string) => Promise<Uint8Array>
  ): Promise<Uint8Array> {
    const cached = this.get(url);
    if (cached) return cached;

    const data = await fetcher(url);
    this.set(url, data);
    return data;
  }

  clear(): void {
    this.entries.clear();
  }
}

function creativeInputSummary(
  shotSpec: ShotSpec,
  prompt: string,
  profile: PersonalVisualPreferenceProfile,
  includeLearnedSignals: boolean,
  includePublicReferences: boolean
): string[] {
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

function creativeSuggestions(
  shotSpec: ShotSpec,
  prompt: string,
  profile: PersonalVisualPreferenceProfile,
  includeLearnedSignals: boolean,
  includePublicReferences: boolean
): CreativeInterpretationPlan["suggestions"] {
  const suggestions: CreativeInterpretationPlan["suggestions"] = [];
  const append = (suggestion: CreativeInterpretationPlan["suggestions"][number]) => {
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
    case "natural":
    case "custom":
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
    default:
      break;
  }

  if (shotSpec.subject.primary === "person" || shotSpec.subject.primary === "people") {
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

  const safetySuggestion: CreativeInterpretationPlan["suggestions"][number] = {
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

function canLearnLocally(event: PersonalLearningEvent): boolean {
  return event.privacy.singlePhoneOnly &&
    !event.privacy.storesRawPhoto &&
    !event.privacy.uploadsLiveCameraFrame &&
    !event.privacy.identityRecognitionAllowed;
}

function outcomeSignal(event: PersonalLearningEvent): number {
  let signal: number;
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
  }

  if (typeof event.userRating === "number") {
    signal += (Math.min(5, Math.max(1, event.userRating)) - 3) / 4;
  }

  if (typeof event.selectedTargetMatch === "number") {
    signal += (Math.min(1, Math.max(0, event.selectedTargetMatch)) - 0.75) * 0.6;
  }

  return Math.min(1, Math.max(-1, signal));
}

function bump<T extends string>(values: Partial<Record<T, number>>, key: T, amount: number): void {
  if (!key || !Number.isFinite(amount)) return;
  values[key] = clampAffinity((values[key] ?? 0) + amount);
}

function clampAffinity(value: number): number {
  return Number.isFinite(value) ? Math.min(1, Math.max(-1, value)) : 0;
}

function containsAny(text: string, terms: string[]): boolean {
  return terms.some((term) => text.includes(term));
}

function compactPromptQuery(prompt: string): string {
  return prompt
    .split(/[^a-z0-9]+/i)
    .filter(Boolean)
    .slice(0, 10)
    .join(" ");
}

function uniqueNonEmpty(values: string[]): string[] {
  return [...new Set(values.map((value) => value.trim()).filter(Boolean))];
}

const requiredCreativeInterpretationMustNotSendTerms = [
  "raw_live_camera_feed",
  "private_photo",
  "face_identity",
  "precise_location_without_consent",
  "raw_learning_events",
] as const;

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
] as const;

function isCreativeInterpretationPrivacySafe(
  privacy: CreativeInterpretationPlan["privacy"]
): boolean {
  return privacy.singlePhoneOnly &&
    privacy.requiresUserConsent &&
    !privacy.sendsRawCameraFrame &&
    !privacy.sendsPrivatePhoto &&
    !privacy.sendsIdentityData &&
    !privacy.sendsPreciseLocation &&
    !privacy.sendsRawLearningEvents &&
    !privacy.allowsGenerativeOutput;
}

function blockedCreativeInterpretationPayloadTerms(
  plan: CreativeInterpretationPlan
): string[] {
  const inspectedText = [
    ...plan.inputSummary,
    ...plan.suggestions.flatMap((suggestion) => [suggestion.title, suggestion.instruction]),
  ].join(" ").toLowerCase();

  return creativeInterpretationBlockedPayloadTerms.filter((term) => inspectedText.includes(term));
}

function creativeInterpretationGuidanceFromRequest(request: CreativeInterpretationRequest): string[] {
  let remainingWords = request.maxResponseWords;
  const guidance: string[] = [];
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
} as const;

function openAICreativeInterpretationInputText(request: CreativeInterpretationRequest): string {
  const summary = request.inputSummary
    .slice(0, 8)
    .map((item) => `- ${item}`)
    .join("\n");
  const suggestions = request.suggestionBriefs
    .slice(0, 6)
    .map((item) => `- ${item}`)
    .join("\n");
  const allowedInputs = request.allowedInputs.join(", ");

  return [
    "LensPilot creative interpretation request.",
    `Plan id: ${request.planId}`,
    `Allowed input classes: ${allowedInputs}`,
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

function firstOpenAIOutputText(output: unknown): string | undefined {
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

function cleanProviderText(value: string, maxLength: number): string {
  const collapsed = value
    .split(/\s+/)
    .join(" ")
    .trim();
  return collapsed.length <= maxLength ? collapsed : collapsed.slice(0, maxLength).trim();
}

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
] as const;

function uniqueSources(
  results: OnlineInspirationResult[],
  fallback: OnlineInspirationSource
): OnlineInspirationSource[] {
  const sources = [...new Set(results.map((result) => result.source))];
  return sources.length > 0 ? sources : [fallback];
}

function aggregateSinglePhoneAiDiagnosticsStatus(
  checks: SinglePhoneAiDiagnosticCheck[]
): SinglePhoneAiDiagnosticsStatus {
  if (checks.some((check) => check.status === "blocked")) return "blocked";
  if (checks.some((check) => check.status === "attention")) return "attention";
  return "passed";
}

function referencePopupDiagnosticCheck(referencePhoto?: ReferencePhotoState): SinglePhoneAiDiagnosticCheck {
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

function onlineReferencePlanDiagnosticCheck(plan?: OnlineReferencePlan): SinglePhoneAiDiagnosticCheck {
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

function onlineProviderHealthDiagnosticCheck(
  snapshot?: OnlineInspirationHealthSnapshot
): SinglePhoneAiDiagnosticCheck {
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
  }
}

function localLearningDiagnosticCheck(profile: PersonalVisualPreferenceProfile): SinglePhoneAiDiagnosticCheck {
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

function calibrationReadinessDiagnosticCheck(
  report?: TargetMatchCalibrationReadinessReport
): SinglePhoneAiDiagnosticCheck {
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

function learningStoreDiagnosticCheck(
  profile: PersonalVisualPreferenceProfile,
  protection: PersonalVisualProfileStorageProtection
): SinglePhoneAiDiagnosticCheck {
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

function captureCoachingDiagnosticCheck(
  summary?: CaptureCoachingSummary
): SinglePhoneAiDiagnosticCheck {
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

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function pageIndex(value: unknown): number {
  return isRecord(value) && typeof value.index === "number" ? value.index : Number.MAX_SAFE_INTEGER;
}

function metadataValue(value: unknown): string | undefined {
  if (!isRecord(value) || typeof value.value !== "string") return undefined;
  const cleaned = cleanText(value.value);
  return cleaned || undefined;
}

function cleanText(value: string): string {
  return value
    .replace(/<[^>]+>/g, "")
    .replace(/&quot;/g, "\"")
    .replace(/&amp;/g, "&")
    .trim();
}

function openverseLicenseLabel(license?: string, version?: string): string | undefined {
  const cleanedLicense = license?.trim();
  if (!cleanedLicense) return undefined;

  const normalized = cleanedLicense.toLowerCase();
  if (normalized === "pdm") return "Public Domain Mark";
  if (normalized === "cc0") return "CC0";

  const cleanedVersion = version?.trim();
  return cleanedVersion ? `CC ${cleanedLicense.toUpperCase()} ${cleanedVersion}` : `CC ${cleanedLicense.toUpperCase()}`;
}

function inferredMimeType(url?: string): string | undefined {
  if (!url) return undefined;
  const pathname = new URL(url, "https://lenspilot.local").pathname.toLowerCase();
  if (pathname.endsWith(".jpg") || pathname.endsWith(".jpeg")) return "image/jpeg";
  if (pathname.endsWith(".png")) return "image/png";
  if (pathname.endsWith(".webp")) return "image/webp";
  if (pathname.endsWith(".gif")) return "image/gif";
  return undefined;
}

function diversifyScoredResults<T extends { result: OnlineInspirationResult; index: number; score: number }>(
  ranked: T[]
): T[] {
  const selectedIds = new Set<string>();
  const selectedSources = new Set<OnlineInspirationSource>();
  const diversified: T[] = [];

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

function scoreOnlineInspirationResult(
  result: OnlineInspirationResult,
  originalIndex: number,
  queryOrder: Map<string, number>,
  queryTokens: Set<string>
): number {
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

function tokenizeForRanking(value: string): string[] {
  return value
    .toLowerCase()
    .split(/[^a-z0-9]+/i)
    .filter((token) => token.length > 2);
}
