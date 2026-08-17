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

const thumbnailCache = makeThumbnailMemoryCache(1);
thumbnailCache.set("https://example.test/first.jpg", new Uint8Array([1]));
thumbnailCache.set("https://example.test/second.jpg", new Uint8Array([2]));
assert(!thumbnailCache.get("https://example.test/first.jpg"), "Thumbnail cache should evict oldest entries.");
assert(thumbnailCache.get("https://example.test/second.jpg")[0] === 2, "Thumbnail cache should keep the latest entry.");

console.log(JSON.stringify({
  personalLearning: true,
  onlineReferencePlan: plan.reason,
  onlineSourceAdapter: [...new Set(rankedReferences.map((result) => result.source))].join("+"),
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
