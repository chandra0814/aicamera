const fs = require("node:fs");
const path = require("node:path");

const calibrationPath = path.resolve(process.cwd(), "../../tests/calibration/target-match-calibration.json");
const manifest = JSON.parse(fs.readFileSync(calibrationPath, "utf8"));

const scenarios = [
  {
    id: "portrait",
    domain: "portrait",
    preferredGuidanceReason: "improve_subject_background_separation",
    rankedWeaknesses: ["subjectPosition", "lighting"],
    targetSampleCount: 3,
  },
  {
    id: "landscape",
    domain: "landscape",
    preferredGuidanceReason: "ready_to_capture",
    rankedWeaknesses: ["composition", "cameraAngle"],
    targetSampleCount: 3,
  },
  {
    id: "sky",
    domain: "landscape",
    preferredGuidanceReason: "increase_sky",
    rankedWeaknesses: ["composition", "exposure"],
    targetSampleCount: 3,
  },
  {
    id: "clutter",
    domain: "portrait",
    preferredGuidanceReason: "reduce_clutter",
    rankedWeaknesses: ["background", "composition"],
    targetSampleCount: 3,
  },
  {
    id: "backlight",
    domain: "portrait",
    preferredGuidanceReason: "improve_face_light",
    rankedWeaknesses: ["lighting", "exposure"],
    targetSampleCount: 3,
  },
  {
    id: "horizon",
    domain: "landscape",
    preferredGuidanceReason: "level_horizon",
    rankedWeaknesses: ["horizon", "cameraAngle"],
    targetSampleCount: 3,
  },
  {
    id: "motion",
    domain: "lifestyle",
    preferredGuidanceReason: "reduce_motion_blur",
    rankedWeaknesses: ["sharpnessProbability", "pose"],
    targetSampleCount: 3,
  },
  {
    id: "night",
    domain: "night",
    preferredGuidanceReason: "protect_highlights",
    rankedWeaknesses: ["exposure", "sharpnessProbability"],
    targetSampleCount: 3,
  },
];

const allowedDomains = new Set(["portrait", "landscape", "lifestyle", "night"]);
const requiredScenarioIds = ["portrait", "landscape", "sky", "clutter", "backlight", "horizon", "motion", "night"];
const manifestScenarioIds = manifest.collectionPlan?.requiredScenarios ?? [];

assert(scenarios.length === 8, "Calibration queue should cover eight guided scenarios.");
assert(requiredScenarioIds.every((id) => scenarios.some((scenario) => scenario.id === id)), "Calibration queue is missing a required scenario.");
assert(scenarios.reduce((sum, scenario) => sum + scenario.targetSampleCount, 0) === 24, "Calibration queue should target 24 real captures.");
assert(new Set(scenarios.map((scenario) => scenario.id)).size === scenarios.length, "Calibration scenario IDs should be unique.");
assert(scenarios.every((scenario) => allowedDomains.has(scenario.domain)), "Calibration scenarios should map to supported manifest domains.");
assert(["portrait", "landscape", "lifestyle", "night"].every((domain) => scenarios.some((scenario) => scenario.domain === domain)), "Calibration queue should cover every supported domain.");
assert(Array.isArray(manifestScenarioIds), "Calibration manifest should list requiredScenarios.");
assert(JSON.stringify(manifestScenarioIds) === JSON.stringify(scenarios.map((scenario) => scenario.id)), "Calibration manifest requiredScenarios should match the guided capture queue.");
assert(manifest.collectionPlan?.realCaptureTargetCount === requiredSampleCount(), "Calibration manifest target count should match the guided capture queue.");
assert(scenarios.find((scenario) => scenario.id === "sky")?.preferredGuidanceReason === "increase_sky", "Sky calibration should target sky guidance.");
assert(scenarios.find((scenario) => scenario.id === "motion")?.rankedWeaknesses.includes("sharpnessProbability"), "Motion calibration should include sharpness weakness.");

let progress = emptyProgress();
progress = selectScenario(progress, "sky");
progress = recordCapture(progress, "sky");
progress = recordCapture(progress, "sky");
progress = recordCapture(progress, "sky");
progress = recordCapture(progress, "sky");

assert(progress.activeScenarioId === "sky", "Selecting a calibration scenario should persist the active scenario.");
assert(completedCount(progress, "sky") === 3, "Calibration scenario progress should cap at the target count.");
assert(completedSampleCount(progress) === 3, "Completed sample count should aggregate sanitized scenario counts.");
assert(isComplete(progress, "sky"), "Scenario should be complete after its target count.");

const sanitizedProgress = sanitizeProgress({
  version: "legacy",
  activeScenarioId: "upload_private_photo",
  completedCounts: {
    portrait: -4,
    landscape: 2.8,
    sky: 99,
    external_cloud_album: 7,
  },
});

assert(sanitizedProgress.version === "1.0", "Stored queue progress should use the current schema version.");
assert(!sanitizedProgress.activeScenarioId, "Stored queue progress should drop unknown active scenarios.");
assert(!sanitizedProgress.completedCounts.portrait, "Stored queue progress should drop negative counts.");
assert(sanitizedProgress.completedCounts.landscape === 2, "Stored queue progress should truncate numeric counts.");
assert(sanitizedProgress.completedCounts.sky === 3, "Stored queue progress should cap oversized counts.");
assert(!sanitizedProgress.completedCounts.external_cloud_album, "Stored queue progress should drop unknown scenario counts.");

console.log(JSON.stringify({
  calibrationCaptureQueue: true,
  scenarios: scenarios.map((scenario) => scenario.id),
  targetRealCaptureSamples: requiredSampleCount(),
  domains: [...new Set(scenarios.map((scenario) => scenario.domain))],
  status: "passed",
}, null, 2));

function emptyProgress() {
  return {
    version: "1.0",
    completedCounts: {},
  };
}

function selectScenario(progress, scenarioId) {
  return sanitizeProgress({
    ...progress,
    activeScenarioId: scenarioId,
  });
}

function recordCapture(progress, scenarioId) {
  const current = completedCount(progress, scenarioId);
  const scenario = scenarioById(scenarioId);
  return sanitizeProgress({
    ...progress,
    completedCounts: {
      ...progress.completedCounts,
      [scenarioId]: Math.min(scenario.targetSampleCount, current + 1),
    },
  });
}

function completedCount(progress, scenarioId) {
  const scenario = scenarioById(scenarioId);
  const value = progress.completedCounts[scenarioId] ?? 0;
  if (!Number.isFinite(value)) return 0;
  return Math.min(scenario.targetSampleCount, Math.max(0, Math.trunc(value)));
}

function completedSampleCount(progress) {
  return scenarios.reduce((sum, scenario) => sum + completedCount(progress, scenario.id), 0);
}

function requiredSampleCount() {
  return scenarios.reduce((sum, scenario) => sum + scenario.targetSampleCount, 0);
}

function isComplete(progress, scenarioId) {
  const scenario = scenarioById(scenarioId);
  return completedCount(progress, scenarioId) >= scenario.targetSampleCount;
}

function sanitizeProgress(progress) {
  const activeScenarioId = scenarioExists(progress.activeScenarioId) ? progress.activeScenarioId : undefined;
  const completedCounts = Object.fromEntries(
    scenarios
      .map((scenario) => [scenario.id, completedCount(progress, scenario.id)])
      .filter(([, count]) => count > 0)
  );

  return {
    version: "1.0",
    activeScenarioId,
    completedCounts,
  };
}

function scenarioById(scenarioId) {
  return scenarios.find((scenario) => scenario.id === scenarioId) ?? scenarios[0];
}

function scenarioExists(scenarioId) {
  return typeof scenarioId === "string" && scenarios.some((scenario) => scenario.id === scenarioId);
}

function assert(condition, message) {
  if (!condition) {
    console.error(message);
    process.exit(1);
  }
}
