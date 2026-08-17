const fs = require("node:fs");
const path = require("node:path");

const repoRoot = findRepoRoot();
const defaultManifestPath = path.join(repoRoot, "tests/calibration/target-match-calibration.json");

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

if (require.main === module || globalThis.__LENSPILOT_RUN_PROMOTION_CLI__) {
  runCli(getCliArgs());
}

function runCli(argv) {
  try {
    const options = parseArgs(argv);
    if (options.help) {
      printHelp();
      return;
    }

    assert(options.candidatePath, "Missing --candidate <path>.");
    const candidate = readJson(resolveInputPath(options.candidatePath));
    const promotedSample = promoteCandidate(candidate, options);

    if (options.write) {
      const manifestPath = resolveInputPath(options.manifestPath ?? defaultManifestPath);
      const manifest = readJson(manifestPath);
      appendSample(manifest, promotedSample);
      fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
      console.error(`Promoted ${candidate.id} to ${promotedSample.id} in ${manifestPath}.`);
      return;
    }

    console.log(JSON.stringify(promotedSample, null, 2));
  } catch (error) {
    console.error(error.message);
    process.exit(1);
  }
}

function promoteCandidate(candidate, options = {}) {
  assert(candidate?.sampleKind === "iphone_capture_candidate", "Only iphone_capture_candidate samples can be promoted.");
  assert(typeof candidate.id === "string" && candidate.id.length > 0, "Candidate id is required.");
  assert(typeof candidate.prompt === "string" && candidate.prompt.length > 0, `${candidate.id}: prompt is required.`);
  assert(candidate.captureMetadata?.capturedAt, `${candidate.id}: captureMetadata.capturedAt is required.`);
  assert(candidate.captureMetadata?.deviceModel, `${candidate.id}: captureMetadata.deviceModel is required.`);
  assert(candidate.deviceCapability?.physicalCameras?.length > 0, `${candidate.id}: deviceCapability.physicalCameras is required.`);
  assert(candidate.sceneState?.safety?.movementGuidanceAllowed !== undefined, `${candidate.id}: sceneState.safety is required.`);
  assert(candidate.targetMatch, `${candidate.id}: targetMatch snapshot is required.`);
  assert(candidate.privacy?.singlePhoneOnly === true, `${candidate.id}: singlePhoneOnly must be true.`);
  assert(candidate.privacy?.cloudAnalysisUsed !== true, `${candidate.id}: cloudAnalysisUsed must be false.`);
  assert(candidate.privacy?.generativeEditsAllowed !== true, `${candidate.id}: generativeEditsAllowed must be false.`);
  assert(candidate.privacy?.identityRecognitionAllowed !== true, `${candidate.id}: identityRecognitionAllowed must be false.`);

  const reviewCount = Number(options.reviewCount);
  assert(Number.isInteger(reviewCount) && reviewCount >= 2, "Blind review count must be an integer >= 2.");
  assert(typeof options.preferredGuidanceReason === "string" && options.preferredGuidanceReason.length > 0, "Missing --preferred-guidance-reason <reason>.");
  assert(Array.isArray(options.rankedWeaknesses) && options.rankedWeaknesses.length > 0, "Missing --weaknesses <metric,metric>.");

  const tolerance = options.tolerance ?? 0.02;
  assert(typeof tolerance === "number" && tolerance > 0 && tolerance <= 0.25, "Tolerance must be > 0 and <= 0.25.");

  const sampleId = options.sampleId ?? candidate.id.replace(/^candidate_/, "iphone_capture_");
  assert(/^[A-Za-z0-9][A-Za-z0-9_-]*$/.test(sampleId), "Sample id must use only letters, numbers, underscores, or hyphens.");

  const domain = options.domain ?? candidate.shotSpec?.domain ?? inferDomain(candidate.prompt);
  assert(["portrait", "landscape", "lifestyle", "night"].includes(domain), `Unsupported calibration domain: ${domain}.`);

  return {
    id: sampleId,
    version: candidate.version,
    sampleKind: "iphone_capture",
    sourceCandidateId: candidate.id,
    domain,
    prompt: candidate.prompt,
    captureMetadata: candidate.captureMetadata,
    privacy: {
      singlePhoneOnly: true,
      cloudAnalysisUsed: false,
      generativeEditsAllowed: false,
      identityRecognitionAllowed: false,
    },
    deviceCapability: candidate.deviceCapability,
    sceneState: candidate.sceneState,
    blindPreference: {
      reviewCount,
      preferredGuidanceReason: options.preferredGuidanceReason,
      rankedWeaknesses: options.rankedWeaknesses,
      notes: options.notes ?? "",
    },
    expected: {
      singlePhoneOnly: true,
      targetMatch: makeExpectedTargetMatch(candidate.targetMatch, tolerance),
    },
  };
}

function appendSample(manifest, sample) {
  assert(Array.isArray(manifest.samples), "Calibration manifest needs a samples array.");
  assert(!manifest.samples.some((existing) => existing.id === sample.id), `Calibration sample already exists: ${sample.id}.`);
  manifest.samples.push(sample);
  return manifest;
}

function makeExpectedTargetMatch(targetMatch, tolerance) {
  return Object.fromEntries(targetMatchMetrics.map((metric) => {
    assert(typeof targetMatch[metric] === "number", `Candidate targetMatch.${metric} is required.`);
    return [metric, {
      min: roundScore(clamp01(targetMatch[metric] - tolerance)),
      max: roundScore(clamp01(targetMatch[metric] + tolerance)),
    }];
  }));
}

function parseArgs(argv) {
  const options = { rankedWeaknesses: undefined };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--help" || arg === "-h") {
      options.help = true;
    } else if (arg === "--candidate") {
      options.candidatePath = takeValue(argv, ++index, arg);
    } else if (arg === "--manifest") {
      options.manifestPath = takeValue(argv, ++index, arg);
    } else if (arg === "--sample-id") {
      options.sampleId = takeValue(argv, ++index, arg);
    } else if (arg === "--domain") {
      options.domain = takeValue(argv, ++index, arg);
    } else if (arg === "--review-count") {
      options.reviewCount = Number(takeValue(argv, ++index, arg));
    } else if (arg === "--preferred-guidance-reason") {
      options.preferredGuidanceReason = takeValue(argv, ++index, arg);
    } else if (arg === "--weaknesses") {
      options.rankedWeaknesses = takeValue(argv, ++index, arg).split(",").map((value) => value.trim()).filter(Boolean);
    } else if (arg === "--notes") {
      options.notes = takeValue(argv, ++index, arg);
    } else if (arg === "--tolerance") {
      options.tolerance = Number(takeValue(argv, ++index, arg));
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

function inferDomain(prompt) {
  const normalized = prompt.toLowerCase();
  if (normalized.includes("night")) return "night";
  if (normalized.includes("portrait") || normalized.includes("me") || normalized.includes("person")) return "portrait";
  if (normalized.includes("landscape") || normalized.includes("sky") || normalized.includes("sunset")) return "landscape";
  return "lifestyle";
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

function roundScore(value) {
  return Math.round(value * 10_000) / 10_000;
}

function clamp01(value) {
  return Math.max(0, Math.min(1, value));
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function printHelp() {
  console.log(`Usage:
  node scripts/promote-calibration-candidate.cjs --candidate <candidate.json> --sample-id <stable_id> --review-count 2 --preferred-guidance-reason <reason> --weaknesses background,lighting [--write]

Options:
  --candidate <path>                 Exported iphone_capture_candidate JSON from the app.
  --manifest <path>                  Calibration manifest to append to when --write is set.
  --sample-id <id>                   Stable manifest id. Defaults from the candidate id.
  --domain <domain>                  portrait, landscape, lifestyle, or night. Defaults from ShotSpec/prompt.
  --review-count <number>            Number of blind reviewers. Must be 2 or more.
  --preferred-guidance-reason <text> Winning guidance reason from blind review.
  --weaknesses <metric,metric>       Ranked weakness labels from blind review.
  --notes <text>                     Optional reviewer notes.
  --tolerance <number>               Expected Target Match range padding. Defaults to 0.02.
  --write                            Append to the manifest instead of printing the promoted sample.
`);
}

module.exports = {
  appendSample,
  inferDomain,
  makeExpectedTargetMatch,
  promoteCandidate,
  targetMatchMetrics,
};
