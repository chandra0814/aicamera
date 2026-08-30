const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const repoRoot = findRepoRoot();
const defaultManifestPath = path.join(repoRoot, "tests/calibration/target-match-calibration.json");

const calibrationScenarios = [
  {
    id: "portrait",
    title: "Portrait",
    domain: "portrait",
    prompt: "Give me a cinematic portrait with natural skin and a clean background.",
  },
  {
    id: "landscape",
    title: "Landscape",
    domain: "landscape",
    prompt: "Capture a wide landscape with strong composition and natural color.",
  },
  {
    id: "sky",
    title: "Sky",
    domain: "landscape",
    prompt: "Show more sky in a dramatic but realistic landscape photo.",
  },
  {
    id: "clutter",
    title: "Clutter",
    domain: "portrait",
    prompt: "Give me a portrait with a cleaner background and less clutter.",
  },
  {
    id: "backlight",
    title: "Backlight",
    domain: "portrait",
    prompt: "Make a backlit portrait with visible face detail and protected highlights.",
  },
  {
    id: "horizon",
    title: "Horizon",
    domain: "landscape",
    prompt: "Capture a landscape with a level horizon and balanced framing.",
  },
  {
    id: "motion",
    title: "Motion",
    domain: "lifestyle",
    prompt: "Capture a lifestyle action photo with sharp subject detail.",
  },
  {
    id: "night",
    title: "Night",
    domain: "night",
    prompt: "Capture a low-light night photo with stable sharp detail.",
  },
];
const scenarioById = Object.fromEntries(calibrationScenarios.map((scenario) => [scenario.id, scenario]));

if (require.main === module || globalThis.__LENSPILOT_RUN_READINESS_CLI__) {
  runCli(getCliArgs());
}

function runCli(argv) {
  try {
    const options = parseArgs(argv);
    if (options.help) {
      printHelp();
      return;
    }

    const manifestPath = resolveInputPath(options.manifestPath ?? defaultManifestPath);
    const manifest = readJson(manifestPath);
    const validationSummary = validateManifest(manifestPath);
    const report = makeReadinessReport(manifest, validationSummary, manifestPath);

    if (options.json) {
      console.log(JSON.stringify(report, null, 2));
      return;
    }

    printHumanReport(report);
  } catch (error) {
    console.error(error.message);
    process.exit(1);
  }
}

function makeReadinessReport(manifest, validationSummary, manifestPath) {
  const requiredDomains = manifest.collectionPlan?.requiredDomains ?? [];
  const requiredScenarios = manifest.collectionPlan?.requiredScenarios ?? [];
  const scenarioTargetCount = requiredScenarios.length > 0
    ? Math.max(1, Math.floor(manifest.collectionPlan.realCaptureTargetCount / requiredScenarios.length))
    : 0;
  const domainTargets = Object.fromEntries(requiredDomains.map((domain) => [domain, 0]));
  const domainCounts = Object.fromEntries(requiredDomains.map((domain) => [domain, 0]));
  const scenarioCounts = Object.fromEntries(requiredScenarios.map((scenarioId) => [scenarioId, 0]));

  for (const scenarioId of requiredScenarios) {
    const domain = scenarioById[scenarioId]?.domain;
    if (domain && Object.hasOwn(domainTargets, domain)) {
      domainTargets[domain] += scenarioTargetCount;
    }
  }

  for (const sample of manifest.samples ?? []) {
    if (sample.sampleKind !== "iphone_capture") continue;
    if (Object.hasOwn(domainCounts, sample.domain)) {
      domainCounts[sample.domain] += 1;
    }

    const scenarioId = sample.captureMetadata?.calibrationScenarioId;
    const scenario = scenarioById[scenarioId];
    if (!scenario || !Object.hasOwn(scenarioCounts, scenarioId)) continue;
    if (sample.domain !== scenario.domain) continue;
    scenarioCounts[scenarioId] += 1;
  }

  const domains = requiredDomains.map((domain) => {
    const targetCount = domainTargets[domain] || 1;
    const reviewedCount = domainCounts[domain] ?? 0;
    return {
      id: domain,
      reviewedCount,
      targetCount,
      missingCount: Math.max(0, targetCount - reviewedCount),
      isComplete: reviewedCount >= targetCount,
    };
  });
  const scenarios = requiredScenarios.map((scenarioId) => {
    const scenario = scenarioById[scenarioId] ?? {
      id: scenarioId,
      title: scenarioId,
      domain: "unknown",
      prompt: "",
    };
    const reviewedCount = scenarioCounts[scenarioId] ?? 0;
    return {
      id: scenario.id,
      title: scenario.title,
      domain: scenario.domain,
      prompt: scenario.prompt,
      reviewedCount,
      targetCount: scenarioTargetCount,
      missingCount: Math.max(0, scenarioTargetCount - reviewedCount),
      isComplete: reviewedCount >= scenarioTargetCount,
    };
  });
  const nextScenario = scenarios.find((scenario) => !scenario.isComplete) ?? null;

  return {
    manifestPath,
    calibrationVersion: validationSummary.calibrationVersion,
    status: validationSummary.calibrationReadiness,
    reviewedSampleCount: validationSummary.realCaptureSamples,
    targetRealCaptureCount: validationSummary.targetRealCaptureSamples,
    missingSampleCount: validationSummary.missingRealCaptureSamples,
    missingDomains: validationSummary.missingRealCaptureDomains,
    missingScenarios: validationSummary.missingRealCaptureScenarios,
    domains,
    scenarios,
    nextScenario,
    validationStatus: validationSummary.status,
  };
}

function validateManifest(manifestPath) {
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

  return JSON.parse(validator.stdout);
}

function printHumanReport(report) {
  console.log(`Calibration readiness: ${report.status}`);
  console.log(`Manifest: ${report.manifestPath}`);
  console.log(`Reviewed captures: ${report.reviewedSampleCount}/${report.targetRealCaptureCount}`);
  console.log(`Missing captures: ${report.missingSampleCount}`);
  console.log("");
  console.log("Domains:");
  for (const domain of report.domains) {
    console.log(`${domain.isComplete ? "[x]" : "[ ]"} ${domain.id}: ${domain.reviewedCount}/${domain.targetCount}`);
  }
  console.log("");
  console.log("Scenarios:");
  for (const scenario of report.scenarios) {
    console.log(`${scenario.isComplete ? "[x]" : "[ ]"} ${scenario.title} (${scenario.domain}): ${scenario.reviewedCount}/${scenario.targetCount}`);
  }

  if (report.nextScenario) {
    console.log("");
    console.log(`Next capture: ${report.nextScenario.title}`);
    console.log(`Prompt: ${report.nextScenario.prompt}`);
  }
}

function parseArgs(argv) {
  const options = {};

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--help" || arg === "-h") {
      options.help = true;
    } else if (arg === "--json") {
      options.json = true;
    } else if (arg === "--manifest") {
      options.manifestPath = takeValue(argv, ++index, arg);
    } else if (!arg.startsWith("--") && !options.manifestPath) {
      options.manifestPath = arg;
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
  npm run calibration:readiness -- [--manifest <target-match-calibration.json>] [--json]

Options:
  --manifest <path>    Calibration manifest to inspect. Defaults to tests/calibration/target-match-calibration.json.
  --json               Print the checklist as JSON for automation.
`);
}

module.exports = {
  makeReadinessReport,
};
