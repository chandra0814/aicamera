const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const repoRoot = findRepoRoot();
const scriptPath = path.join(repoRoot, "shared/typescript/scripts/import-reviewed-calibration-batch.cjs");
const manifest = readJson(path.join(repoRoot, "tests/calibration/target-match-calibration.json"));
const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "lenspilot-calibration-batch-test-"));

try {
  const exportDir = path.join(tempDir, "reviewed-exports");
  fs.mkdirSync(exportDir, { recursive: true });
  const firstSample = makeReviewedExport({
    id: "iphone_capture_batch_clutter_01",
    sourceCandidateId: "candidate_batch_clutter_01",
    capturedAt: "2026-09-02T20:30:00Z",
  });
  const secondSample = makeReviewedExport({
    id: "iphone_capture_batch_clutter_02",
    sourceCandidateId: "candidate_batch_clutter_02",
    capturedAt: "2026-09-02T20:31:00Z",
  });
  const firstPath = path.join(exportDir, "iphone_capture_batch_clutter_01.reviewed.json");
  const secondPath = path.join(exportDir, "iphone_capture_batch_clutter_02.reviewed.json");
  fs.writeFileSync(firstPath, `${JSON.stringify(firstSample, null, 2)}\n`);
  fs.writeFileSync(secondPath, `${JSON.stringify(secondSample, null, 2)}\n`);

  const tempFixturesDir = path.join(tempDir, "tests/fixtures");
  const tempCalibrationDir = path.join(tempDir, "tests/calibration");
  fs.mkdirSync(tempFixturesDir, { recursive: true });
  fs.mkdirSync(tempCalibrationDir, { recursive: true });
  for (const fixture of ["iphone-device-capability.json", "portrait-scene-state.json"]) {
    fs.copyFileSync(path.join(repoRoot, "tests/fixtures", fixture), path.join(tempFixturesDir, fixture));
  }
  const manifestPath = path.join(tempCalibrationDir, "target-match-calibration.json");
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
  const originalManifestJson = fs.readFileSync(manifestPath, "utf8");

  const validateOnlyResult = runBatchImporter(["--dir", exportDir, "--manifest", manifestPath, "--json"]);
  const validateOnlySummary = JSON.parse(validateOnlyResult.stdout);
  assert(validateOnlySummary.reviewedBatchImport === true, "Batch import should expose a stable summary flag.");
  assert(validateOnlySummary.write === false, "Batch import should default to validate-only mode.");
  assert(validateOnlySummary.reviewedExportCount === 2, "Batch import should read both reviewed exports.");
  assert(validateOnlySummary.reviewedSampleCount === 2, "Batch import should report post-import reviewed sample count.");
  assert(validateOnlySummary.missingSampleCount === 22, "Batch import should report remaining real-capture count.");
  assert(validateOnlySummary.importedSampleIds[0] === firstSample.id, "Batch import should sort source files deterministically.");
  assert(validateOnlySummary.privacy.singlePhoneOnly === true, "Batch import summary must stay single-phone only.");
  assert(validateOnlySummary.privacy.importsRawPhotos === false, "Batch import must not import raw photos.");
  assert(fs.readFileSync(manifestPath, "utf8") === originalManifestJson, "Validate-only batch import must not write the manifest.");

  const writeResult = runBatchImporter(["--dir", exportDir, "--manifest", manifestPath, "--write", "--json"]);
  const writeSummary = JSON.parse(writeResult.stdout);
  assert(writeSummary.write === true, "Batch import write mode should be reported.");
  assert(writeResult.stderr.includes("Imported 2 reviewed calibration samples"), "Batch import should print safe write metadata.");
  assert(writeResult.stderr.includes("Calibration readiness: needs_more_samples (2/24 captures)."), "Batch import should print readiness after write.");
  const writtenManifest = readJson(manifestPath);
  const writtenManifestJson = fs.readFileSync(manifestPath, "utf8");
  assert(writtenManifest.samples.some((sample) => sample.id === firstSample.id), "Batch write should append the first reviewed sample.");
  assert(writtenManifest.samples.some((sample) => sample.id === secondSample.id), "Batch write should append the second reviewed sample.");

  const duplicateDir = path.join(tempDir, "duplicate-exports");
  fs.mkdirSync(duplicateDir, { recursive: true });
  fs.writeFileSync(path.join(duplicateDir, "a.reviewed.json"), `${JSON.stringify(firstSample, null, 2)}\n`);
  fs.writeFileSync(path.join(duplicateDir, "b.reviewed.json"), `${JSON.stringify({ ...firstSample, sourceCandidateId: "candidate_duplicate" }, null, 2)}\n`);
  const duplicateResult = runBatchImporter(["--dir", duplicateDir, "--manifest", manifestPath, "--write"], { expectFailure: true });
  assert(duplicateResult.stderr.includes(`Duplicate reviewed sample id ${firstSample.id}`), "Batch import should reject duplicate sample ids before writing.");
  assert(fs.readFileSync(manifestPath, "utf8") === writtenManifestJson, "Duplicate rejection must preserve the manifest.");

  const unsafeDir = path.join(tempDir, "unsafe-exports");
  fs.mkdirSync(unsafeDir, { recursive: true });
  fs.writeFileSync(path.join(unsafeDir, "unsafe.reviewed.json"), `${JSON.stringify({
    ...makeReviewedExport({
      id: "iphone_capture_batch_unsafe",
      sourceCandidateId: "candidate_batch_unsafe",
      capturedAt: "2026-09-02T20:32:00Z",
    }),
    privacy: {
      singlePhoneOnly: true,
      cloudAnalysisUsed: true,
      generativeEditsAllowed: false,
      identityRecognitionAllowed: false,
    },
  }, null, 2)}\n`);
  fs.writeFileSync(path.join(unsafeDir, "a-valid.reviewed.json"), JSON.stringify(makeReviewedExport({
    id: "iphone_capture_batch_valid_before_unsafe",
    sourceCandidateId: "candidate_batch_valid_before_unsafe",
    capturedAt: "2026-09-02T20:33:00Z",
  })));
  const unsafeResult = runBatchImporter(["--dir", unsafeDir, "--manifest", manifestPath, "--write"], { expectFailure: true });
  assert(unsafeResult.stderr.includes("privacy.cloudAnalysisUsed must be false"), "Batch import should reject cloud-analysis calibration exports.");
  assert(fs.readFileSync(manifestPath, "utf8") === writtenManifestJson, "A mixed valid and unsafe batch must not partially write.");

  const invalidManifestPath = path.join(tempCalibrationDir, "invalid-manifest.json");
  const invalidManifest = structuredClone(manifest);
  invalidManifest.samples[0].sceneStatePath = "../fixtures/missing-scene.json";
  fs.writeFileSync(invalidManifestPath, JSON.stringify(invalidManifest));
  const invalidManifestJson = fs.readFileSync(invalidManifestPath, "utf8");
  runBatchImporter(["--dir", exportDir, "--manifest", invalidManifestPath, "--write"], { expectFailure: true });
  assert(fs.readFileSync(invalidManifestPath, "utf8") === invalidManifestJson, "Manifest validation failure must preserve the original file.");
  assert(!fs.readdirSync(tempCalibrationDir).some((name) => name.startsWith(".target-match-calibration.import-")), "Validation must clean up temporary manifests on success and failure.");

  console.log(JSON.stringify({
    calibrationBatchImport: true,
    reviewedExportCount: validateOnlySummary.reviewedExportCount,
    writeMode: writeSummary.write,
    duplicateRejected: true,
    unsafeExportRejected: true,
    status: "passed",
  }, null, 2));
} finally {
  fs.rmSync(tempDir, { recursive: true, force: true });
}

function makeReviewedExport({ id, sourceCandidateId, capturedAt }) {
  return {
    id,
    version: "2026.09.02",
    sampleKind: "iphone_capture",
    sourceCandidateId,
    domain: "portrait",
    prompt: "Give me a portrait with a cleaner background and less clutter.",
    captureMetadata: {
      capturedAt,
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
    blindPreference: {
      reviewCount: 2,
      preferredGuidanceReason: "reduce_clutter",
      rankedWeaknesses: ["background", "lighting"],
      notes: "Batch import validation fixture.",
    },
    expected: {
      singlePhoneOnly: true,
      targetMatch: Object.fromEntries(targetMatchMetrics().map((metric) => [metric, { min: 0, max: 1 }])),
    },
  };
}

function targetMatchMetrics() {
  return [
    "composition",
    "subjectPosition",
    "cameraAngle",
    "lighting",
    "background",
    "horizon",
    "pose",
    "sharpnessProbability",
    "exposure",
    "intentMatch",
    "overall",
  ];
}

function runBatchImporter(args, options = {}) {
  const result = spawnSync(process.execPath, [
    "-e",
    `globalThis.__LENSPILOT_RUN_BATCH_IMPORT_CLI__ = true; const fs = require("node:fs"); eval(fs.readFileSync(${JSON.stringify(scriptPath)}, "utf8"));`,
    "--",
    ...args,
  ], {
    cwd: path.join(repoRoot, "shared/typescript"),
    encoding: "utf8",
  });

  if (options.expectFailure) {
    assert(result.status !== 0, `Expected batch importer to fail. stdout=${JSON.stringify(result.stdout)} stderr=${JSON.stringify(result.stderr)}`);
    return result;
  }

  if (result.status !== 0) {
    process.stdout.write(result.stdout);
    process.stderr.write(result.stderr);
    process.exit(result.status ?? 1);
  }

  return result;
}

function findRepoRoot() {
  const candidates = [
    path.resolve(process.cwd(), "../.."),
    path.resolve(__dirname, "../../.."),
    process.cwd(),
  ];

  for (const candidate of candidates) {
    if (fs.existsSync(path.join(candidate, "tests/calibration/target-match-calibration.json"))) {
      return candidate;
    }
  }

  throw new Error("Unable to locate LensPilot repo root.");
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}
