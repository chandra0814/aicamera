const fs = require("node:fs");

const readJson = (relativePath) => JSON.parse(fs.readFileSync(relativePath, "utf8"));
const sceneState = readJson("../../tests/fixtures/portrait-scene-state.json");
const deviceCapability = readJson("../../tests/fixtures/iphone-device-capability.json");
const shotSpec = readJson("../../tests/fixtures/cinematic-portrait.shotspec.json");

if (shotSpec.constraints.singlePhoneOnly !== true) {
  throw new Error("ShotSpec must be single-phone only.");
}

if (shotSpec.subject.identityRecognitionAllowed !== false) {
  throw new Error("Identity recognition must stay disabled.");
}

const recommendedLens = deviceCapability.physicalCameras.some((camera) => camera.lensType === "telephoto") ? "telephoto" : "wide";
const horizon = clamp01(1 - Math.abs(sceneState.scene.horizon.rollDegrees) / 12);
const exposure = clamp01(1 - sceneState.scene.lighting.highlightClipping * 0.8 - sceneState.scene.lighting.shadowClipping * 0.6);
const targetMatch = average([
  horizon,
  exposure,
  sceneState.composition.subjectPlacementScore,
  sceneState.composition.balanceScore,
  1 - sceneState.motion.blurRisk,
]);
const nextAction = sceneState.background.clutterScore > 0.55 && sceneState.safety.movementGuidanceAllowed
  ? "if_safe_move_left"
  : "hold_steady";

console.log(JSON.stringify({
  singlePhoneOnly: shotSpec.constraints.singlePhoneOnly,
  recommendedLens,
  targetMatch: Number(targetMatch.toFixed(3)),
  nextAction,
}, null, 2));

function average(values) {
  return clamp01(values.reduce((sum, value) => sum + clamp01(value), 0) / values.length);
}

function clamp01(value) {
  return Math.max(0, Math.min(1, value));
}
