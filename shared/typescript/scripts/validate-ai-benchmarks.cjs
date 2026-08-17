const fs = require("node:fs");

const readJson = (relativePath) => JSON.parse(fs.readFileSync(relativePath, "utf8"));
const suite = readJson("../../tests/benchmarks/ai-guidance-benchmarks.json");
const deviceCapability = readJson("../../tests/fixtures/iphone-device-capability.json");
const calibrationManifest = readJson("../../tests/calibration/target-match-calibration.json");
const calibration = calibrationManifest.targetMatchCalibration;
const guidanceCalibration = guidanceCalibrationFromManifest(calibrationManifest);

for (const benchmark of suite.cases) {
  const shotSpec = parseIntent(benchmark.prompt);
  const shotPlan = plan(shotSpec, benchmark.sceneState, deviceCapability);
  const guidanceAction = selectNextAction(shotPlan, shotSpec.domain, guidanceCalibration);
  const targetMatch = scoreTargetMatch(shotSpec, shotPlan, benchmark.sceneState, calibration);
  const expected = benchmark.expected;

  assert(shotSpec.constraints.singlePhoneOnly === true, `${benchmark.id}: ShotSpec must stay single-phone only.`);
  assert(shotSpec.constraints.cloudAllowed === false, `${benchmark.id}: cloud must remain disabled for benchmark guidance.`);
  assert(shotSpec.constraints.generativeEditsAllowed === false, `${benchmark.id}: generative edits must remain disabled.`);
  assert(shotSpec.subject.identityRecognitionAllowed === false, `${benchmark.id}: identity recognition must stay disabled.`);
  assert(shotSpec.domain === expected.domain, `${benchmark.id}: expected domain ${expected.domain}, got ${shotSpec.domain}.`);
  assert(
    shotPlan.cameraControls.recommendedLens === expected.recommendedLens,
    `${benchmark.id}: expected lens ${expected.recommendedLens}, got ${shotPlan.cameraControls.recommendedLens}.`
  );

  if (typeof expected.targetExposureBias === "number") {
    assert(
      shotPlan.cameraControls.targetExposureBias === expected.targetExposureBias,
      `${benchmark.id}: expected exposure bias ${expected.targetExposureBias}, got ${shotPlan.cameraControls.targetExposureBias}.`
    );
  }

  if (expected.guidance) {
    assert(guidanceAction, `${benchmark.id}: expected a guidance action.`);
    assert(guidanceAction.actor === expected.guidance.actor, `${benchmark.id}: expected actor ${expected.guidance.actor}, got ${guidanceAction.actor}.`);
    assert(guidanceAction.action === expected.guidance.action, `${benchmark.id}: expected action ${expected.guidance.action}, got ${guidanceAction.action}.`);
    assert(guidanceAction.reason === expected.guidance.reason, `${benchmark.id}: expected reason ${expected.guidance.reason}, got ${guidanceAction.reason}.`);
    if (expected.guidance.safetyQualifier) {
      assert(
        guidanceAction.safetyQualifier === expected.guidance.safetyQualifier,
        `${benchmark.id}: expected safety qualifier ${expected.guidance.safetyQualifier}, got ${guidanceAction.safetyQualifier}.`
      );
    }
  }

  checkMinimum(expected.minOverallTargetMatch, targetMatch.overall, "overall Target Match", benchmark.id);
  checkMaximum(expected.maxBackgroundScore, targetMatch.background, "background score", benchmark.id);
  checkMaximum(expected.maxHorizonScore, targetMatch.horizon, "horizon score", benchmark.id);
  checkMaximum(expected.maxExposureScore, targetMatch.exposure, "exposure score", benchmark.id);
  checkMaximum(expected.maxSharpnessProbability, targetMatch.sharpnessProbability, "sharpness probability", benchmark.id);
  checkMaximum(expected.maxLightingScore, targetMatch.lighting, "lighting score", benchmark.id);
}

console.log(JSON.stringify({
  benchmarkVersion: suite.version,
  cases: suite.cases.length,
  status: "passed",
}, null, 2));

function parseIntent(intent) {
  const normalized = intent.toLowerCase();
  const isPortrait = normalized.includes("portrait") || normalized.includes("me") || normalized.includes("person");
  const isLandscape = normalized.includes("landscape") || normalized.includes("sky") || normalized.includes("sunset");
  const isNight = normalized.includes("night");
  const wantsCinematic = normalized.includes("cinematic") || normalized.includes("dramatic");
  const wantsSky = normalized.includes("sky") || normalized.includes("sunset");
  const wantsCleanBackground = normalized.includes("clean") || normalized.includes("background");
  const domain = isNight ? "night" : isPortrait ? "portrait" : isLandscape ? "landscape" : "lifestyle";

  return {
    id: "shot_benchmark",
    version: "1.0",
    source: "text",
    originalPrompt: intent,
    domain,
    subject: {
      primary: isPortrait ? "person" : isLandscape ? "landscape" : "unknown",
      count: isPortrait ? 1 : undefined,
      priority: isLandscape ? "environment" : "subject",
      identityRecognitionAllowed: false,
    },
    style: {
      name: wantsCinematic ? "cinematic" : "natural",
      mood: wantsCinematic ? "dramatic" : "bright",
      colorIntent: wantsCinematic ? "warm_highlights_cool_shadows" : "natural",
      skinTreatment: isPortrait ? "natural" : "none",
    },
    composition: {
      framing: isPortrait ? "environmental" : "wide",
      headroom: isPortrait ? "balanced" : undefined,
      skyPriority: wantsSky ? "high" : undefined,
      backgroundPriority: wantsCleanBackground ? "clean" : wantsSky ? "sunset" : "contextual",
      horizonPlacement: isLandscape ? "lower_third" : "auto",
    },
    cameraIntent: {
      targetLens: isPortrait ? "two_x_if_available" : "wide",
      perspective: isPortrait ? "eye_level" : "auto",
      exposureStrategy: wantsSky ? "protect_highlights" : isPortrait ? "prioritize_faces" : "balanced",
      focusStrategy: isPortrait ? "subject_eye" : "auto",
      depthIntent: isPortrait ? "strong_subject_separation" : "deep_focus",
    },
    constraints: {
      realityMode: "natural",
      cloudAllowed: false,
      generativeEditsAllowed: false,
      userSafetyStrictness: "conservative",
      singlePhoneOnly: true,
    },
    confidence: 0.72,
    missingInfo: [],
  };
}

function plan(shotSpec, sceneState, deviceCapability) {
  const recommendedLens = recommendLens(shotSpec, deviceCapability);
  const targetZoom = recommendedLens === "telephoto" ? 2 : 1;
  const isPortrait = shotSpec.domain === "portrait";
  const photographerChanges = photographerGuidance(sceneState);
  const subjectDirections = subjectGuidance(shotSpec, sceneState);

  return {
    cameraControls: {
      recommendedLens,
      targetZoom,
      targetExposureBias: shotSpec.cameraIntent.exposureStrategy === "protect_highlights" ? -0.3 : 0,
    },
    photographerChanges,
    subjectDirections,
    compositionTarget: {
      subjectBounds: isPortrait
        ? { x: 0.3, y: 0.18, width: 0.4, height: 0.66 }
        : { x: 0.05, y: 0.05, width: 0.9, height: 0.9 },
    },
  };
}

function photographerGuidance(sceneState) {
  const actions = [];
  const horizon = sceneState.scene.horizon;

  if (horizon && Math.abs(horizon.rollDegrees) > 2.5) {
    actions.push(action({
      id: "level_horizon",
      actor: "photographer",
      action: horizon.rollDegrees > 0 ? "rotate_counterclockwise" : "rotate_clockwise",
      confidence: horizon.confidence,
      reason: "level_horizon",
      expectedGain: 0.14,
      safetyQualifier: "if_safe",
      priority: 95,
    }));
  }

  if (
    sceneState.background.clutterScore > 0.55 &&
    sceneState.safety.movementGuidanceAllowed &&
    sceneState.background.cleanerDirection &&
    sceneState.background.cleanerDirection !== "unknown"
  ) {
    actions.push(action({
      id: "reduce_background_clutter",
      actor: "photographer",
      action: directionAction(sceneState.background.cleanerDirection),
      confidence: 0.76,
      reason: "reduce_clutter",
      expectedGain: 0.16,
      safetyQualifier: "if_safe",
      priority: 88,
    }));
  }

  if (sceneState.motion.blurRisk > 0.55) {
    actions.push(action({
      id: "hold_steady",
      actor: "photographer",
      action: "hold_steady",
      confidence: 0.82,
      reason: "reduce_motion_blur",
      expectedGain: 0.18,
      priority: 90,
    }));
  }

  if (sceneState.scene.lighting.highlightClipping > 0.22) {
    actions.push(action({
      id: "protect_highlights",
      actor: "camera",
      action: "adjust_exposure",
      confidence: 0.8,
      reason: "protect_highlights",
      expectedGain: 0.12,
      priority: 82,
    }));
  }

  return actions.length ? actions : [
    action({
      id: "hold_steady_ready",
      actor: "photographer",
      action: "hold_steady",
      confidence: 0.74,
      reason: "ready_to_capture",
      expectedGain: 0.04,
      priority: 50,
    }),
  ];
}

function subjectGuidance(shotSpec, sceneState) {
  if (shotSpec.domain !== "portrait" || (sceneState.scene.lighting.faceLightQuality ?? 0.7) >= 0.55) {
    return [];
  }

  return [
    action({
      id: "turn_toward_light",
      actor: "subject",
      action: "turn_face",
      confidence: 0.68,
      reason: "improve_face_light",
      expectedGain: 0.12,
      priority: 72,
    }),
  ];
}

function action(input) {
  return {
    ttlMs: 3500,
    suppressOppositeUntilMs: 5000,
    ...input,
  };
}

function selectNextAction(shotPlan, domain, guidanceCalibration) {
  return [...shotPlan.photographerChanges, ...shotPlan.subjectDirections]
    .filter((candidate) => candidate.confidence >= 0.55 && candidate.expectedGain >= 0.04)
    .sort((a, b) => actionScore(b, domain, guidanceCalibration) - actionScore(a, domain, guidanceCalibration))[0];
}

function actionScore(candidate, domain, guidanceCalibration) {
  const ease = candidate.actor === "camera" ? 0.95 : candidate.safetyQualifier === "if_safe" ? 0.72 : 0.8;
  const interactionCost = candidate.actor === "subject" ? 0.08 : 0.04;
  const safetyRisk = candidate.safetyQualifier === "if_safe" ? 0.08 : 0;
  return candidate.expectedGain * candidate.confidence * ease - interactionCost - safetyRisk + candidate.priority / 1000 + guidanceBoost(candidate, domain, guidanceCalibration);
}

function recommendLens(shotSpec, deviceCapability) {
  if (
    shotSpec.cameraIntent.targetLens === "two_x_if_available" &&
    deviceCapability.physicalCameras.some((camera) => camera.lensType === "telephoto" || (camera.maxZoom ?? 1) >= 2)
  ) {
    return "telephoto";
  }

  return "wide";
}

function directionAction(direction) {
  if (direction === "left") return "move_left";
  if (direction === "right") return "move_right";
  if (direction === "forward") return "move_forward";
  return "if_safe_move";
}

function scoreTargetMatch(shotSpec, shotPlan, sceneState, calibration) {
  const subject = sceneState.subjects[0];
  const subjectPosition = subject ? rectSimilarity(subject.bounds, shotPlan.compositionTarget.subjectBounds) : 0.25;
  const horizon = sceneState.scene.horizon
    ? clamp01(1 - Math.abs(sceneState.scene.horizon.rollDegrees) / Math.max(calibration.horizonRollFullPenaltyDegrees, 0.001))
    : calibration.missingHorizonScore;
  const exposure = clamp01(
    1 -
      sceneState.scene.lighting.highlightClipping * calibration.highlightClippingPenalty -
      sceneState.scene.lighting.shadowClipping * calibration.shadowClippingPenalty
  );
  const background = clamp01(
    1 -
      sceneState.background.clutterScore * calibration.backgroundClutterPenalty -
      sceneState.background.poleBehindHeadRisk * calibration.poleBehindHeadPenalty
  );
  const lighting = clamp01(
    (sceneState.scene.lighting.faceLightQuality ?? calibration.missingFaceLightQuality) -
      sceneState.scene.lighting.dynamicRangeRisk * calibration.dynamicRangeLightingPenalty
  );
  const pose = clamp01(subject?.face?.eyeOpenProbability ?? calibration.missingPoseScore);
  const sharpnessProbability = clamp01(1 - sceneState.motion.blurRisk * calibration.motionBlurPenalty);
  const composition = average([subjectPosition, sceneState.composition.balanceScore, sceneState.composition.subjectPlacementScore]);
  const pitch = sceneState.cameraState.pitchDegrees ?? 0;
  const cameraAngle = shotSpec.cameraIntent.perspective === "eye_level"
    ? clamp01(1 - Math.abs(pitch) / Math.max(calibration.eyeLevelPitchFullPenaltyDegrees, 0.001))
    : calibration.nonPortraitCameraAngleScore;
  const intentMatch = average([composition, lighting, background, exposure]);
  const scores = { composition, subjectPosition, cameraAngle, lighting, background, horizon, pose, sharpnessProbability, exposure, intentMatch };

  return { ...scores, overall: average(Object.values(scores)) };
}

function rectSimilarity(a, b) {
  const centerDistance = Math.hypot(a.x + a.width / 2 - (b.x + b.width / 2), a.y + a.height / 2 - (b.y + b.height / 2));
  const sizeDistance = Math.abs(a.width * a.height - b.width * b.height);
  return clamp01(1 - centerDistance * 1.8 - sizeDistance);
}

function checkMinimum(expected, actual, label, benchmarkId) {
  if (typeof expected !== "number") return;
  assert(actual >= expected, `${benchmarkId}: expected ${label} >= ${expected}, got ${actual}.`);
}

function checkMaximum(expected, actual, label, benchmarkId) {
  if (typeof expected !== "number") return;
  assert(actual <= expected, `${benchmarkId}: expected ${label} <= ${expected}, got ${actual}.`);
}

function guidanceCalibrationFromManifest(manifest) {
  const globalReasonBoosts = {};
  const domainReasonBoosts = {};
  const minimumReviewers = Math.max(1, manifest.collectionPlan.minimumBlindReviewers);

  for (const sample of manifest.samples) {
    const preference = sample.blindPreference;
    if (sample.sampleKind !== "iphone_capture" || !preference || preference.reviewCount < minimumReviewers) {
      continue;
    }

    const reviewScale = Math.min(3, preference.reviewCount / minimumReviewers);
    addGuidanceBoost(preference.preferredGuidanceReason, sample.domain, 0.02 * reviewScale, globalReasonBoosts, domainReasonBoosts);

    preference.rankedWeaknesses.slice(0, 3).forEach((weakness, index) => {
      const reason = preferredReasonForWeakness(weakness);
      if (!reason) return;
      addGuidanceBoost(reason, sample.domain, 0.006 * reviewScale / (index + 1), globalReasonBoosts, domainReasonBoosts);
    });
  }

  return {
    globalReasonBoosts: clampBoosts(globalReasonBoosts),
    domainReasonBoosts: Object.fromEntries(
      Object.entries(domainReasonBoosts).map(([domain, boosts]) => [domain, clampBoosts(boosts)])
    ),
  };
}

function addGuidanceBoost(reason, domain, amount, globalReasonBoosts, domainReasonBoosts) {
  if (!isGuidanceReason(reason)) return;

  if (domain && isCaptureDomain(domain)) {
    domainReasonBoosts[domain] ??= {};
    domainReasonBoosts[domain][reason] = (domainReasonBoosts[domain][reason] ?? 0) + amount;
  } else {
    globalReasonBoosts[reason] = (globalReasonBoosts[reason] ?? 0) + amount;
  }
}

function guidanceBoost(candidate, domain, guidanceCalibration) {
  const globalBoost = guidanceCalibration.globalReasonBoosts[candidate.reason] ?? 0;
  const domainBoost = domain ? guidanceCalibration.domainReasonBoosts[domain]?.[candidate.reason] ?? 0 : 0;
  return clampBoost(globalBoost + domainBoost);
}

function clampBoost(value) {
  return Math.max(0, Math.min(0.08, Number.isFinite(value) ? value : 0));
}

function clampBoosts(boosts) {
  return Object.fromEntries(
    Object.entries(boosts).map(([reason, boost]) => [reason, clampBoost(boost)])
  );
}

function preferredReasonForWeakness(weakness) {
  if (weakness === "background") return "reduce_clutter";
  if (weakness === "horizon") return "level_horizon";
  if (weakness === "lighting") return "improve_face_light";
  if (weakness === "exposure") return "protect_highlights";
  if (weakness === "pose") return "improve_pose";
  if (weakness === "sharpnessProbability") return "reduce_motion_blur";
  if (weakness === "composition" || weakness === "subjectPosition") return "improve_subject_background_separation";
  if (weakness === "cameraAngle" || weakness === "intentMatch") return "match_reference";
  return undefined;
}

function isGuidanceReason(value) {
  return [
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
  ].includes(value);
}

function isCaptureDomain(value) {
  return ["portrait", "landscape", "travel", "lifestyle", "night", "reference"].includes(value);
}

function average(values) {
  return clamp01(values.reduce((sum, value) => sum + clamp01(value), 0) / values.length);
}

function clamp01(value) {
  return Math.max(0, Math.min(1, value));
}

function assert(condition, message) {
  if (!condition) {
    console.error(message);
    process.exit(1);
  }
}
