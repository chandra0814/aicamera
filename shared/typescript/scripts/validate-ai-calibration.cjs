const fs = require("node:fs");
const path = require("node:path");

const calibrationPath = path.resolve("../../tests/calibration/target-match-calibration.json");
const calibrationRoot = path.dirname(calibrationPath);
const manifest = readJson(calibrationPath);
const weights = manifest.targetMatchCalibration;

const requiredWeights = [
  "horizonRollFullPenaltyDegrees",
  "eyeLevelPitchFullPenaltyDegrees",
  "highlightClippingPenalty",
  "shadowClippingPenalty",
  "backgroundClutterPenalty",
  "poleBehindHeadPenalty",
  "dynamicRangeLightingPenalty",
  "motionBlurPenalty",
  "missingHorizonScore",
  "missingFaceLightQuality",
  "missingPoseScore",
  "nonPortraitCameraAngleScore",
];

assert(manifest.collectionPlan?.singlePhoneOnly === true, "Calibration plan must stay single-phone only.");
assert(Array.isArray(manifest.samples) && manifest.samples.length > 0, "Calibration manifest needs at least one seed or capture sample.");

for (const key of requiredWeights) {
  assert(typeof weights?.[key] === "number", `Missing numeric calibration weight: ${key}.`);
}

assert(weights.horizonRollFullPenaltyDegrees > 0, "horizonRollFullPenaltyDegrees must be positive.");
assert(weights.eyeLevelPitchFullPenaltyDegrees > 0, "eyeLevelPitchFullPenaltyDegrees must be positive.");
assertRange(weights.highlightClippingPenalty, "highlightClippingPenalty", 0, 2);
assertRange(weights.shadowClippingPenalty, "shadowClippingPenalty", 0, 2);
assertRange(weights.backgroundClutterPenalty, "backgroundClutterPenalty", 0, 2);
assertRange(weights.poleBehindHeadPenalty, "poleBehindHeadPenalty", 0, 2);
assertRange(weights.dynamicRangeLightingPenalty, "dynamicRangeLightingPenalty", 0, 2);
assertRange(weights.motionBlurPenalty, "motionBlurPenalty", 0, 2);
assertRange(weights.missingHorizonScore, "missingHorizonScore", 0, 1);
assertRange(weights.missingFaceLightQuality, "missingFaceLightQuality", 0, 1);
assertRange(weights.missingPoseScore, "missingPoseScore", 0, 1);
assertRange(weights.nonPortraitCameraAngleScore, "nonPortraitCameraAngleScore", 0, 1);

let realCaptureSamples = 0;

for (const sample of manifest.samples) {
  assert(typeof sample.id === "string" && sample.id.length > 0, "Calibration sample needs an id.");
  assert(["fixture_seed", "iphone_capture_candidate", "iphone_capture"].includes(sample.sampleKind), `${sample.id}: unsupported sampleKind ${sample.sampleKind}.`);
  assert(typeof sample.prompt === "string" && sample.prompt.length > 0, `${sample.id}: prompt is required.`);

  const deviceCapability = readSampleJson(sample.deviceCapabilityPath, sample.deviceCapability, sample.id, "device capability");
  const sceneState = readSampleJson(sample.sceneStatePath, sample.sceneState, sample.id, "scene state");
  assert(deviceCapability.physicalCameras?.length > 0, `${sample.id}: device capability must include physical cameras.`);
  assert(sceneState.safety?.movementGuidanceAllowed !== undefined, `${sample.id}: scene safety state is required.`);
  assert(sample.privacy?.singlePhoneOnly !== false, `${sample.id}: calibration samples must stay single-phone only.`);
  assert(sample.privacy?.cloudAnalysisUsed !== true, `${sample.id}: calibration samples must not require cloud analysis.`);
  assert(sample.privacy?.identityRecognitionAllowed !== true, `${sample.id}: calibration samples must not include identity recognition.`);

  if (sample.sampleKind === "iphone_capture_candidate" || sample.sampleKind === "iphone_capture") {
    assert(sample.captureMetadata?.capturedAt, `${sample.id}: real captures need captureMetadata.capturedAt.`);
    assert(sample.captureMetadata?.deviceModel, `${sample.id}: real captures need captureMetadata.deviceModel.`);
  }

  if (sample.sampleKind === "iphone_capture") {
    realCaptureSamples += 1;
    assert((sample.blindPreference?.reviewCount ?? 0) >= manifest.collectionPlan.minimumBlindReviewers, `${sample.id}: real captures need blind preference reviews.`);
  }

  const shotSpec = parseIntent(sample.prompt);
  assert(shotSpec.constraints.singlePhoneOnly === true, `${sample.id}: ShotSpec must stay single-phone only.`);
  assert(shotSpec.constraints.cloudAllowed === false, `${sample.id}: cloud guidance must stay off for calibration.`);
  assert(shotSpec.subject.identityRecognitionAllowed === false, `${sample.id}: identity recognition must stay disabled.`);

  const targetMatch = scoreTargetMatch(shotSpec, sceneState, weights);
  if (sample.expected?.targetMatch) {
    checkExpectedTargetMatch(sample.expected.targetMatch, targetMatch, sample.id);
  } else {
    assert(sample.sampleKind === "iphone_capture_candidate", `${sample.id}: expected targetMatch ranges are required before a sample can gate calibration.`);
  }
}

console.log(JSON.stringify({
  calibrationVersion: manifest.version,
  samples: manifest.samples.length,
  realCaptureSamples,
  targetRealCaptureSamples: manifest.collectionPlan.realCaptureTargetCount,
  status: "passed",
}, null, 2));

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function readSampleJson(relativePath, inlineValue, sampleId, label) {
  if (inlineValue) return inlineValue;
  assert(typeof relativePath === "string" && relativePath.length > 0, `${sampleId}: ${label} path or inline value is required.`);
  return readJson(path.resolve(calibrationRoot, relativePath));
}

function parseIntent(intent) {
  const normalized = intent.toLowerCase();
  const isPortrait = normalized.includes("portrait") || normalized.includes("me") || normalized.includes("person");
  const isLandscape = normalized.includes("landscape") || normalized.includes("sky") || normalized.includes("sunset");
  const isNight = normalized.includes("night");
  const wantsCinematic = normalized.includes("cinematic") || normalized.includes("dramatic");
  const wantsSky = normalized.includes("sky") || normalized.includes("sunset");

  return {
    domain: isNight ? "night" : isPortrait ? "portrait" : isLandscape ? "landscape" : "lifestyle",
    subject: {
      primary: isPortrait ? "person" : isLandscape ? "landscape" : "unknown",
      identityRecognitionAllowed: false,
    },
    style: {
      name: wantsCinematic ? "cinematic" : "natural",
    },
    cameraIntent: {
      perspective: isPortrait ? "eye_level" : "auto",
      exposureStrategy: wantsSky ? "protect_highlights" : isPortrait ? "prioritize_faces" : "balanced",
    },
    constraints: {
      cloudAllowed: false,
      generativeEditsAllowed: false,
      singlePhoneOnly: true,
    },
  };
}

function scoreTargetMatch(shotSpec, sceneState, calibration) {
  const subject = sceneState.subjects[0];
  const target = shotSpec.domain === "portrait"
    ? { x: 0.3, y: 0.18, width: 0.4, height: 0.66 }
    : subject?.bounds ?? { x: 0.05, y: 0.05, width: 0.9, height: 0.9 };
  const subjectPosition = subject ? rectSimilarity(subject.bounds, target) : 0.25;
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

function checkExpectedTargetMatch(expected, actual, sampleId) {
  assert(expected, `${sampleId}: expected targetMatch ranges are required.`);

  for (const [metric, bounds] of Object.entries(expected)) {
    assert(metric in actual, `${sampleId}: unknown Target Match metric ${metric}.`);
    if (typeof bounds.min === "number") {
      assert(actual[metric] >= bounds.min, `${sampleId}: expected ${metric} >= ${bounds.min}, got ${actual[metric]}.`);
    }
    if (typeof bounds.max === "number") {
      assert(actual[metric] <= bounds.max, `${sampleId}: expected ${metric} <= ${bounds.max}, got ${actual[metric]}.`);
    }
  }
}

function rectSimilarity(a, b) {
  const centerDistance = Math.hypot(a.x + a.width / 2 - (b.x + b.width / 2), a.y + a.height / 2 - (b.y + b.height / 2));
  const sizeDistance = Math.abs(a.width * a.height - b.width * b.height);
  return clamp01(1 - centerDistance * 1.8 - sizeDistance);
}

function average(values) {
  return clamp01(values.reduce((sum, value) => sum + clamp01(value), 0) / values.length);
}

function assertRange(value, label, min, max) {
  assert(value >= min && value <= max, `${label} must be between ${min} and ${max}.`);
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
