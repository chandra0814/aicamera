import type { CaptureDomain, ShotSpec } from "./contracts";
import type { GuidanceAction } from "./planning";
import { defaultGuidanceCalibration, type GuidanceCalibration } from "./ai-core";

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

export interface OnlineInspirationRequest {
  planId: string;
  queries: string[];
  perQueryLimit: number;
  source: "wikimedia_commons";
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
  source: "wikimedia_commons";
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

export interface OnlineInspirationResponse {
  planId: string;
  source: "wikimedia_commons";
  results: OnlineInspirationResult[];
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
    source: "wikimedia_commons",
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

  return { planId: request.planId, source: request.source, results };
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

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function pageIndex(value: unknown): number {
  return isRecord(value) && typeof value.index === "number" ? value.index : Number.MAX_SAFE_INTEGER;
}

function metadataValue(value: unknown): string | undefined {
  if (!isRecord(value) || typeof value.value !== "string") return undefined;
  const cleaned = value.value
    .replace(/<[^>]+>/g, "")
    .replace(/&quot;/g, "\"")
    .replace(/&amp;/g, "&")
    .trim();
  return cleaned || undefined;
}
