const fs = require("node:fs");
const path = require("node:path");

const repoRoot = findRepoRoot();
const scriptDir = findScriptDir();
const defaultManifestPath = path.join(repoRoot, "tests/calibration/target-match-calibration.json");
const { appendReviewedSample, normalizeReviewedSample, validateManifest } = loadImporter(scriptDir);

if (require.main === module || globalThis.__LENSPILOT_RUN_BATCH_IMPORT_CLI__) {
  runCli(getCliArgs());
}

function runCli(argv) {
  try {
    const options = parseArgs(argv);
    if (options.help) {
      printHelp();
      return;
    }

    const samplePaths = collectSamplePaths(options);
    assert(samplePaths.length > 0, "No reviewed JSON exports found.");

    const manifestPath = resolveInputPath(options.manifestPath ?? defaultManifestPath);
    const manifest = readJson(manifestPath);
    const normalizedSamples = normalizeBatch(samplePaths);
    const nextManifest = appendBatch(manifest, normalizedSamples.map((entry) => entry.sample));
    const readinessReport = validateManifest(nextManifest, manifestPath);
    const summary = makeBatchSummary({
      manifestPath,
      normalizedSamples,
      readinessReport,
      write: options.write === true,
    });

    if (options.write) {
      fs.writeFileSync(manifestPath, `${JSON.stringify(nextManifest, null, 2)}\n`);
      printWriteSummary(summary);
    }

    if (options.json) {
      console.log(JSON.stringify(summary, null, 2));
    } else {
      printHumanSummary(summary);
    }
  } catch (error) {
    console.error(error.message);
    process.exit(1);
  }
}

function collectSamplePaths(options) {
  const samplePaths = (options.samplePaths ?? []).map(resolveInputPath);

  if (options.directoryPath) {
    samplePaths.push(...listJsonFiles(resolveInputPath(options.directoryPath), options.recursive === true));
  }

  return [...new Set(samplePaths)].sort((left, right) => left.localeCompare(right));
}

function listJsonFiles(directoryPath, recursive) {
  assert(fs.existsSync(directoryPath), `Reviewed export directory does not exist: ${directoryPath}`);
  assert(fs.statSync(directoryPath).isDirectory(), `Reviewed export path is not a directory: ${directoryPath}`);

  const files = [];
  const entries = fs.readdirSync(directoryPath, { withFileTypes: true })
    .filter((entry) => !entry.isSymbolicLink())
    .sort((left, right) => left.name.localeCompare(right.name));

  for (const entry of entries) {
    const entryPath = path.join(directoryPath, entry.name);
    if (entry.isDirectory()) {
      if (recursive) {
        files.push(...listJsonFiles(entryPath, recursive));
      }
      continue;
    }
    if (entry.isFile() && entry.name.toLowerCase().endsWith(".json")) {
      files.push(entryPath);
    }
  }

  return files;
}

function normalizeBatch(samplePaths) {
  const seenIds = new Map();

  return samplePaths.map((samplePath) => {
    const sample = normalizeReviewedSample(readJson(samplePath));
    const existingPath = seenIds.get(sample.id);
    assert(!existingPath, `Duplicate reviewed sample id ${sample.id} in ${existingPath} and ${samplePath}.`);
    seenIds.set(sample.id, samplePath);
    return {
      path: samplePath,
      sample,
    };
  });
}

function appendBatch(manifest, samples) {
  return samples.reduce((nextManifest, sample) => appendReviewedSample(nextManifest, sample), manifest);
}

function makeBatchSummary({ manifestPath, normalizedSamples, readinessReport, write }) {
  const status = readinessReport.calibrationReadiness ?? readinessReport.status;
  const reviewedSampleCount = readinessReport.reviewedSampleCount ?? readinessReport.realCaptureSamples;
  const targetRealCaptureCount = readinessReport.targetRealCaptureCount ?? readinessReport.targetRealCaptureSamples;
  const missingSampleCount = readinessReport.missingRealCaptureSamples ?? readinessReport.missingSampleCount;
  const missingDomains = readinessReport.missingRealCaptureDomains ?? readinessReport.missingDomains ?? [];
  const missingScenarios = readinessReport.missingRealCaptureScenarios ?? readinessReport.missingScenarios ?? [];

  return {
    reviewedBatchImport: true,
    write,
    manifestPath,
    reviewedExportCount: normalizedSamples.length,
    importedSampleIds: normalizedSamples.map((entry) => entry.sample.id),
    sourceFiles: normalizedSamples.map((entry) => entry.path),
    calibrationReadiness: status,
    reviewedSampleCount,
    targetRealCaptureCount,
    missingSampleCount,
    missingDomains,
    missingScenarios,
    privacy: {
      singlePhoneOnly: true,
      importsRawPhotos: false,
      uploadsLiveCameraFrames: false,
      acceptsIdentityData: false,
      acceptsGenerativeEdits: false,
    },
    status: "passed",
  };
}

function printWriteSummary(summary) {
  console.error(`Imported ${summary.reviewedExportCount} reviewed calibration samples into ${summary.manifestPath}.`);
  console.error(`Calibration readiness: ${summary.calibrationReadiness} (${summary.reviewedSampleCount}/${summary.targetRealCaptureCount} captures).`);
  if (summary.missingSampleCount > 0) {
    console.error(`Missing real-capture samples: ${summary.missingSampleCount}.`);
  }
  if (summary.missingDomains.length > 0) {
    console.error(`Missing domains: ${summary.missingDomains.join(", ")}.`);
  }
  if (summary.missingScenarios.length > 0) {
    console.error(`Missing scenarios: ${summary.missingScenarios.join(", ")}.`);
  }
}

function printHumanSummary(summary) {
  console.log(`Reviewed export batch: ${summary.reviewedExportCount} file(s)`);
  console.log(`Manifest: ${summary.manifestPath}`);
  console.log(`Mode: ${summary.write ? "write" : "validate only"}`);
  console.log(`Calibration readiness: ${summary.calibrationReadiness}`);
  console.log(`Reviewed captures: ${summary.reviewedSampleCount}/${summary.targetRealCaptureCount}`);
  console.log(`Missing captures: ${summary.missingSampleCount}`);
  if (summary.missingDomains.length > 0) {
    console.log(`Missing domains: ${summary.missingDomains.join(", ")}`);
  }
  if (summary.missingScenarios.length > 0) {
    console.log(`Missing scenarios: ${summary.missingScenarios.join(", ")}`);
  }
  console.log("");
  console.log("Samples:");
  for (const sampleId of summary.importedSampleIds) {
    console.log(`- ${sampleId}`);
  }
}

function parseArgs(argv) {
  const options = {
    samplePaths: [],
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--help" || arg === "-h") {
      options.help = true;
    } else if (arg === "--dir") {
      options.directoryPath = takeValue(argv, ++index, arg);
    } else if (arg === "--sample") {
      options.samplePaths.push(takeValue(argv, ++index, arg));
    } else if (arg === "--manifest") {
      options.manifestPath = takeValue(argv, ++index, arg);
    } else if (arg === "--write") {
      options.write = true;
    } else if (arg === "--json") {
      options.json = true;
    } else if (arg === "--recursive") {
      options.recursive = true;
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  assert(options.help || options.directoryPath || options.samplePaths.length > 0, "Missing --dir <folder> or --sample <reviewed-sample.json>.");
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

function findScriptDir() {
  const candidates = [
    path.resolve(process.cwd(), "scripts"),
    path.resolve(__dirname),
  ];

  for (const candidate of candidates) {
    if (fs.existsSync(path.join(candidate, "import-reviewed-calibration-sample.cjs"))) {
      return candidate;
    }
  }

  throw new Error("Unable to locate calibration import scripts.");
}

function loadImporter(sourceDir) {
  const moduleShim = { exports: {} };
  const sourcePath = path.join(sourceDir, "import-reviewed-calibration-sample.cjs");
  const source = fs.readFileSync(sourcePath, "utf8");
  const runner = new Function("module", "exports", "require", "__dirname", "__filename", source);
  runner(moduleShim, moduleShim.exports, require, sourceDir, sourcePath);
  return moduleShim.exports;
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
  npm run calibration:import-reviewed-batch -- --dir <reviewed-export-folder> [--write]
  npm run calibration:import-reviewed-batch -- --sample <reviewed-a.json> --sample <reviewed-b.json> [--write]

Options:
  --dir <path>       Folder containing reviewed iphone_capture JSON exports.
  --sample <path>    Reviewed iphone_capture JSON export. Can be repeated.
  --manifest <path>  Calibration manifest to validate or append to.
  --write            Append all reviewed samples to the manifest in one write.
  --json             Print a machine-readable summary.
  --recursive        Include JSON files in nested folders under --dir.
`);
}

module.exports = {
  appendBatch,
  collectSamplePaths,
  makeBatchSummary,
  normalizeBatch,
};
