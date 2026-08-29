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

export interface OnlineInspirationResponse {
  planId: string;
  source: OnlineInspirationSource;
  sources: OnlineInspirationSource[];
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

export const personalVisualProfileStoragePolicy = {
  storageKey: "com.lenspilot.personalVisualProfile.v1",
  maxStoredProfileBytes: 64 * 1024,
  privacy: {
    localOnly: true,
    storesRawPhoto: false,
    uploadsLiveCameraFrame: false,
    storesIdentityData: false,
    cloudPersonalizationSyncAllowed: false,
  },
} as const;

export interface PersonalVisualProfileStorageSnapshot {
  storageKey: string;
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
  storageKey = personalVisualProfileStoragePolicy.storageKey
): PersonalVisualProfileStorageSnapshot {
  const storedProfile = sanitizePersonalVisualPreferenceProfile(profile);
  return {
    storageKey,
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
  return { planId: request.planId, source: request.source, sources: uniqueSources(ranked, request.source), results: ranked };
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

function uniqueSources(
  results: OnlineInspirationResult[],
  fallback: OnlineInspirationSource
): OnlineInspirationSource[] {
  const sources = [...new Set(results.map((result) => result.source))];
  return sources.length > 0 ? sources : [fallback];
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
