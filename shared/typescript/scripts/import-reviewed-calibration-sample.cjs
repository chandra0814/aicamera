const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const repoRoot = findRepoRoot();
const defaultManifestPath = path.join(repoRoot, "tests/calibration/target-match-calibration.json");

const reviewedSampleFields = [
  "id",
  "version",
  "sampleKind",
  "sourceCandidateId",
  "domain",
  "prompt",
  "captureMetadata",
  "privacy",
  "deviceCapability",
  "sceneState",
  "blindPreference",
  "expected",
];

const targetMatchMetrics = [
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

if (require.main === module || globalThis.__LENSPILOT_RUN_IMPORT_CLI__) {
  runCli(getCliArgs());
}

function runCli(argv) {
  try {
    const options = parseArgs(argv);
    if (options.help) {
      printHelp();
      return;
    }

    assert(options.samplePath, "Missing --sample <path>.");
    const reviewedSample = normalizeReviewedSample(readJson(resolveInputPath(options.samplePath)), options);

    if (options.write) {
      const manifestPath = resolveInputPath(options.manifestPath ?? defaultManifestPath);
      const manifest = readJson(manifestPath);
      const nextManifest = appendReviewedSample(manifest, reviewedSample);
      validateManifest(nextManifest);
      fs.writeFileSync(manifestPath, `${JSON.stringify(nextManifest, null, 2)}\n`);
      console.error(`Imported reviewed calibration sample ${reviewedSample.id} into ${manifestPath}.`);
      return;
    }

    console.log(JSON.stringify(reviewedSample, null, 2));
  } catch (error) {
    console.error(error.message);
    process.exit(1);
  }
}

function appendReviewedSample(manifest, sample) {
  const reviewedSample = normalizeReviewedSample(sample);
  assert(Array.isArray(manifest.samples), "Calibration manifest needs a samples array.");
  assert(!manifest.samples.some((existing) => existing.id === reviewedSample.id), `Calibration sample already exists: ${reviewedSample.id}.`);
  return {
    ...manifest,
    samples: [...manifest.samples, reviewedSample],
  };
}

function normalizeReviewedSample(sample, options = {}) {
  assert(sample?.sampleKind === "iphone_capture", "Only reviewed iphone_capture samples can be imported.");
  assert(typeof sample.id === "string" && sample.id.length > 0, "Reviewed sample id is required.");

  const normalized = Object.fromEntries(reviewedSampleFields
    .filter((field) => sample[field] !== undefined)
    .map((field) => [field, sample[field]]));

  if (options.sampleId) {
    normalized.id = options.sampleId;
  }

  validateReviewedSample(normalized);
  return normalized;
}

function validateReviewedSample(sample) {
  assert(/^[A-Za-z0-9][A-Za-z0-9_-]*$/.test(sample.id), "Sample id must use only letters, numbers, underscores, or hyphens.");
  assert(typeof sample.version === "string" && sample.version.length > 0, `${sample.id}: version is required.`);
  assert(typeof sample.sourceCandidateId === "string" && sample.sourceCandidateId.length > 0, `${sample.id}: sourceCandidateId is required.`);
  assert(["portrait", "landscape", "lifestyle", "night"].includes(sample.domain), `${sample.id}: unsupported calibration domain ${sample.domain}.`);
  assert(typeof sample.prompt === "string" && sample.prompt.length > 0, `${sample.id}: prompt is required.`);
  assert(sample.captureMetadata?.capturedAt, `${sample.id}: captureMetadata.capturedAt is required.`);
  assert(sample.captureMetadata?.deviceModel, `${sample.id}: captureMetadata.deviceModel is required.`);
  assert(sample.privacy?.singlePhoneOnly === true, `${sample.id}: privacy.singlePhoneOnly must be true.`);
  assert(sample.privacy?.cloudAnalysisUsed === false, `${sample.id}: privacy.cloudAnalysisUsed must be false.`);
  assert(sample.privacy?.generativeEditsAllowed === false, `${sample.id}: privacy.generativeEditsAllowed must be false.`);
  assert(sample.privacy?.identityRecognitionAllowed === false, `${sample.id}: privacy.identityRecognitionAllowed must be false.`);
  assert(sample.deviceCapability?.physicalCameras?.length > 0, `${sample.id}: deviceCapability.physicalCameras is required.`);
  assert(sample.sceneState?.safety?.movementGuidanceAllowed !== undefined, `${sample.id}: sceneState.safety is required.`);
  assert((sample.blindPreference?.reviewCount ?? 0) >= 2, `${sample.id}: blindPreference.reviewCount must be 2 or more.`);
  assert(typeof sample.blindPreference?.preferredGuidanceReason === "string" && sample.blindPreference.preferredGuidanceReason.length > 0, `${sample.id}: preferredGuidanceReason is required.`);
  assert(Array.isArray(sample.blindPreference?.rankedWeaknesses) && sample.blindPreference.rankedWeaknesses.length > 0, `${sample.id}: rankedWeaknesses are required.`);
  assert(sample.expected?.singlePhoneOnly === true, `${sample.id}: expected.singlePhoneOnly must be true.`);

  for (const metric of targetMatchMetrics) {
    const range = sample.expected?.targetMatch?.[metric];
    assert(typeof range?.min === "number", `${sample.id}: expected.targetMatch.${metric}.min is required.`);
    assert(typeof range?.max === "number", `${sample.id}: expected.targetMatch.${metric}.max is required.`);
    assert(range.min >= 0 && range.max <= 1 && range.min <= range.max, `${sample.id}: invalid expected.targetMatch.${metric} range.`);
  }
}

function validateManifest(manifest) {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "lenspilot-calibration-import-"));

  try {
    const manifestPath = path.join(tempDir, "target-match-calibration.json");
    fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);

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
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

function parseArgs(argv) {
  const options = {};

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--help" || arg === "-h") {
      options.help = true;
    } else if (arg === "--sample") {
      options.samplePath = takeValue(argv, ++index, arg);
    } else if (arg === "--manifest") {
      options.manifestPath = takeValue(argv, ++index, arg);
    } else if (arg === "--sample-id") {
      options.sampleId = takeValue(argv, ++index, arg);
    } else if (arg === "--write") {
      options.write = true;
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return options;
}

function takeValue(argv, index, flag) {
  assert(index < argv.length && !argv[index].startsWith("--"), `${flag} requires a value.`);
  return argv[index];
}

function resolveInputPath(inputPath) {
  return path.isAbsolute(inputPath) ? inputPath : path.resolve(process.cwd(), inputPath);
}

function getCliArgs() {
  if (process.argv[1]?.startsWith("-")) {
    return process.argv.slice(1);
  }

  return process.argv.slice(2);
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

  return path.resolve(process.cwd(), "../..");
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function printHelp() {
  console.log(`Usage:
  npm run calibration:import-reviewed -- --sample <reviewed-sample.json> [--write]

Options:
  --sample <path>      Reviewed iphone_capture JSON exported from the in-app blind review sheet.
  --manifest <path>    Calibration manifest to append to when --write is set.
  --sample-id <id>     Optional stable id override for the manifest entry.
  --write              Append to the manifest instead of printing the normalized reviewed sample.
`);
}

module.exports = {
  appendReviewedSample,
  normalizeReviewedSample,
  validateReviewedSample,
};
