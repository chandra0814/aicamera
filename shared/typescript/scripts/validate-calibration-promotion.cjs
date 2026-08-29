const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const scriptDir = findScriptDir();
const repoRoot = findRepoRoot();
const { appendSample, promoteCandidate } = loadPromoter(scriptDir);
const { appendReviewedSample, normalizeReviewedSample } = loadImporter(scriptDir);
const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "lenspilot-calibration-"));

try {
  const candidate = makeCandidateFixture();
  const promotedSample = promoteCandidate(candidate, {
    sampleId: "iphone_capture_promotion_fixture",
    reviewCount: 2,
    preferredGuidanceReason: "reduce_clutter",
    rankedWeaknesses: ["background", "lighting"],
    notes: "Promotion self-test fixture.",
    tolerance: 0.02,
  });

  assert(promotedSample.sampleKind === "iphone_capture", "Promotion must produce an iphone_capture sample.");
  assert(promotedSample.domain === "portrait", "Promotion should preserve the portrait domain.");
  assert(promotedSample.captureMetadata.calibrationScenarioId === "clutter", "Promotion should preserve calibration scenario metadata.");
  assert(promotedSample.privacy.singlePhoneOnly === true, "Promotion must keep the sample single-phone only.");
  assert(promotedSample.privacy.cloudAnalysisUsed === false, "Promotion must keep cloud analysis disabled.");
  assert(promotedSample.privacy.identityRecognitionAllowed === false, "Promotion must keep identity recognition disabled.");
  assert(promotedSample.expected.targetMatch.overall.min <= candidate.targetMatch.overall, "Overall min should include the candidate score.");
  assert(promotedSample.expected.targetMatch.overall.max >= candidate.targetMatch.overall, "Overall max should include the candidate score.");
  assert(!("shotSpec" in promotedSample), "Promotion output should stay manifest-ready and omit runtime ShotSpec.");

  const manifest = readJson(path.join(repoRoot, "tests/calibration/target-match-calibration.json"));
  const promotionManifest = {
    ...manifest,
    samples: [promotedSample],
  };
  appendSample({ samples: [] }, promotedSample);

  const reviewedExport = makeReviewedExportFixture(candidate, promotedSample);
  const importedSample = normalizeReviewedSample(reviewedExport);
  assert(importedSample.id === promotedSample.id, "Imported sample should preserve the reviewed id.");
  assert(importedSample.sourceCandidateId === candidate.id, "Imported sample should preserve the source candidate id.");
  assert(importedSample.captureMetadata.calibrationScenarioId === "clutter", "Imported sample should preserve calibration scenario metadata.");
  assert(!("shotSpec" in importedSample), "Imported sample should omit app runtime ShotSpec.");
  assert(!("targetMatch" in importedSample), "Imported sample should omit app runtime Target Match snapshot.");
  const importedManifest = appendReviewedSample({ ...manifest, samples: [] }, reviewedExport);
  assert(importedManifest.samples.length === 1, "Importer should append one reviewed sample.");

  const promotionManifestPath = path.join(tempDir, "target-match-calibration.json");
  fs.writeFileSync(promotionManifestPath, `${JSON.stringify(promotionManifest, null, 2)}\n`);
  runCalibrationValidator(promotionManifestPath);

  const importManifestPath = path.join(tempDir, "target-match-calibration-import.json");
  fs.writeFileSync(importManifestPath, `${JSON.stringify(importedManifest, null, 2)}\n`);
  runCalibrationValidator(importManifestPath);

  console.log(JSON.stringify({
    promotedSample: promotedSample.id,
    importedSample: importedSample.id,
    status: "passed",
  }, null, 2));
} finally {
  fs.rmSync(tempDir, { recursive: true, force: true });
}

function makeCandidateFixture() {
  return {
    id: "candidate_frame_portrait_001_1786000000",
    version: "2026.08.17",
    sampleKind: "iphone_capture_candidate",
    prompt: "Give me a cinematic portrait with natural skin and a clean background.",
    captureMetadata: {
      capturedAt: "2026-08-17T13:00:00Z",
      deviceModel: "iPhone MVP Test Device",
      usesFrontCameraForSelfShot: false,
      referencePhotoActive: true,
      calibrationScenarioId: "clutter",
    },
    privacy: {
      singlePhoneOnly: true,
      cloudAnalysisUsed: false,
      generativeEditsAllowed: false,
      identityRecognitionAllowed: false,
    },
    deviceCapability: readJson(path.join(repoRoot, "tests/fixtures/iphone-device-capability.json")),
    sceneState: readJson(path.join(repoRoot, "tests/fixtures/portrait-scene-state.json")),
    shotSpec: readJson(path.join(repoRoot, "tests/fixtures/cinematic-portrait.shotspec.json")),
    shotPlan: readJson(path.join(repoRoot, "tests/fixtures/cinematic-portrait.shotplan.json")),
    guidanceAction: {
      id: "reduce_background_clutter",
      actor: "photographer",
      action: "move_left",
      confidence: 0.76,
      reason: "reduce_clutter",
      expectedGain: 0.16,
      safetyQualifier: "if_safe",
      priority: 88,
      ttlMs: 3500,
      suppressOppositeUntilMs: 5000,
    },
    targetMatch: {
      composition: 0.6548,
      subjectPosition: 0.7744,
      cameraAngle: 0.8857,
      lighting: 0.412,
      background: 0.592,
      horizon: 0.6833,
      pose: 0.91,
      sharpnessProbability: 0.8,
      exposure: 0.808,
      intentMatch: 0.6167,
      overall: 0.7137,
    },
  };
}

function makeReviewedExportFixture(candidate, promotedSample) {
  return {
    ...candidate,
    ...promotedSample,
    sampleKind: "iphone_capture",
    shotSpec: candidate.shotSpec,
    shotPlan: candidate.shotPlan,
    guidanceAction: candidate.guidanceAction,
    targetMatch: candidate.targetMatch,
  };
}

function runCalibrationValidator(manifestPath) {
  const validator = spawnSync(process.execPath, [
    "-e",
    `const fs = require("node:fs"); process.argv[2] = ${JSON.stringify(manifestPath)}; eval(fs.readFileSync("scripts/validate-ai-calibration.cjs", "utf8"));`,
  ], {
    cwd: path.join(repoRoot, "shared/typescript"),
    encoding: "utf8",
  });

  if (validator.status !== 0) {
    process.stdout.write(validator.stdout);
    process.stderr.write(validator.stderr);
    process.exit(validator.status ?? 1);
  }
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function findScriptDir() {
  const candidates = [
    path.resolve(process.cwd(), "scripts"),
    path.resolve(__dirname),
  ];

  for (const candidate of candidates) {
    if (
      fs.existsSync(path.join(candidate, "promote-calibration-candidate.cjs")) &&
      fs.existsSync(path.join(candidate, "import-reviewed-calibration-sample.cjs"))
    ) {
      return candidate;
    }
  }

  throw new Error("Unable to locate calibration promotion scripts.");
}

function findRepoRoot() {
  const candidates = [
    path.resolve(process.cwd(), "../.."),
    path.resolve(scriptDir, "../../.."),
    process.cwd(),
  ];

  for (const candidate of candidates) {
    if (fs.existsSync(path.join(candidate, "tests/calibration/target-match-calibration.json"))) {
      return candidate;
    }
  }

  throw new Error("Unable to locate LensPilot repo root.");
}

function loadPromoter(sourceDir) {
  const moduleShim = { exports: {} };
  const sourcePath = path.join(sourceDir, "promote-calibration-candidate.cjs");
  const source = fs.readFileSync(sourcePath, "utf8");
  const runner = new Function("module", "exports", "require", "__dirname", "__filename", source);
  runner(moduleShim, moduleShim.exports, require, sourceDir, sourcePath);
  return moduleShim.exports;
}

function loadImporter(sourceDir) {
  const moduleShim = { exports: {} };
  const sourcePath = path.join(sourceDir, "import-reviewed-calibration-sample.cjs");
  const source = fs.readFileSync(sourcePath, "utf8");
  const runner = new Function("module", "exports", "require", "__dirname", "__filename", source);
  runner(moduleShim, moduleShim.exports, require, sourceDir, sourcePath);
  return moduleShim.exports;
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}
