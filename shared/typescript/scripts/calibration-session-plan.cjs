const fs = require("node:fs");
const path = require("node:path");

const repoRoot = findRepoRoot();
const defaultManifestPath = path.join(repoRoot, "tests/calibration/target-match-calibration.json");

const scenarioDefinitions = {
  portrait: {
    id: "portrait",
    title: "Portrait",
    domain: "portrait",
    prompt: "Give me a cinematic portrait with natural skin and a clean background.",
    fieldGoal: "Natural face light, clean background separation, and realistic skin tone.",
    captureTip: "Try one indoor window-light portrait, one outdoor shade portrait, and one busier real-world background.",
  },
  landscape: {
    id: "landscape",
    title: "Landscape",
    domain: "landscape",
    prompt: "Capture a wide landscape with strong composition and natural color.",
    fieldGoal: "Balanced framing, natural color, and a clear foreground-to-background read.",
    captureTip: "Use one open view, one foreground object, and one high-dynamic-range scene.",
  },
  sky: {
    id: "sky",
    title: "Sky",
    domain: "landscape",
    prompt: "Show more sky in a dramatic but realistic landscape photo.",
    fieldGoal: "Enough sky for the requested intent while protecting highlights.",
    captureTip: "Use clouds, sunset, or bright sky, but keep the scene realistic and not generated.",
  },
  clutter: {
    id: "clutter",
    title: "Clutter",
    domain: "portrait",
    prompt: "Give me a portrait with a cleaner background and less clutter.",
    fieldGoal: "Detect whether the AI asks for a simpler background or cleaner subject separation.",
    captureTip: "Start from a busier background, then follow the same-phone guidance before capture.",
  },
  backlight: {
    id: "backlight",
    title: "Backlight",
    domain: "portrait",
    prompt: "Make a backlit portrait with visible face detail and protected highlights.",
    fieldGoal: "Recover face detail without blowing out bright background areas.",
    captureTip: "Use a window, doorway, or low sun behind the subject while keeping identity labels out.",
  },
  horizon: {
    id: "horizon",
    title: "Horizon",
    domain: "landscape",
    prompt: "Capture a landscape with a level horizon and balanced framing.",
    fieldGoal: "Verify horizon-level guidance and camera-angle correction.",
    captureTip: "Use a shoreline, road, room edge, or skyline where tilt is easy to notice.",
  },
  motion: {
    id: "motion",
    title: "Motion",
    domain: "lifestyle",
    prompt: "Capture a lifestyle action photo with sharp subject detail.",
    fieldGoal: "Check stability, pose, and motion-blur guidance before selecting the best real frame.",
    captureTip: "Use walking, hand movement, pets, sports, or street action while keeping the same phone in control.",
  },
  night: {
    id: "night",
    title: "Night",
    domain: "night",
    prompt: "Capture a low-light night photo with stable sharp detail.",
    fieldGoal: "Protect highlights, reduce blur, and keep a stable low-light shot plan.",
    captureTip: "Use storefronts, street lights, indoor low light, or evening scenes with no generative edits.",
  },
};

if (require.main === module || globalThis.__LENSPILOT_RUN_SESSION_PLAN_CLI__) {
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
    const plan = makeSessionPlan(manifest, manifestPath);
    const output = options.json ? JSON.stringify(plan, null, 2) : formatMarkdown(plan);

    if (options.outputPath) {
      const outputPath = resolveInputPath(options.outputPath);
      fs.mkdirSync(path.dirname(outputPath), { recursive: true });
      fs.writeFileSync(outputPath, `${output}\n`);
      console.error(`Wrote LensPilot calibration session plan to ${outputPath}.`);
      return;
    }

    console.log(output);
  } catch (error) {
    console.error(error.message);
    process.exit(1);
  }
}

function makeSessionPlan(manifest, manifestPath) {
  assert(manifest.collectionPlan?.singlePhoneOnly === true, "Calibration collection plan must stay single-phone only.");
  assert(Number.isInteger(manifest.collectionPlan.realCaptureTargetCount), "Calibration collection plan must set realCaptureTargetCount.");
  assert(Number.isInteger(manifest.collectionPlan.minimumBlindReviewers), "Calibration collection plan must set minimumBlindReviewers.");
  assert(Array.isArray(manifest.collectionPlan.requiredScenarios), "Calibration collection plan must list requiredScenarios.");
  assert(Array.isArray(manifest.collectionPlan.requiredDomains), "Calibration collection plan must list requiredDomains.");

  const requiredScenarios = manifest.collectionPlan.requiredScenarios;
  const targetRealCaptureCount = manifest.collectionPlan.realCaptureTargetCount;
  const scenarioTargetCount = requiredScenarios.length > 0
    ? Math.max(1, Math.floor(targetRealCaptureCount / requiredScenarios.length))
    : 0;
  const reviewedScenarioCounts = reviewedCountsByScenario(manifest, requiredScenarios);
  const reviewedDomainCounts = reviewedCountsByDomain(manifest, manifest.collectionPlan.requiredDomains);
  const scenarios = requiredScenarios.map((scenarioId) => {
    const definition = scenarioDefinitions[scenarioId];
    assert(definition, `Unsupported calibration scenario: ${scenarioId}.`);
    return {
      ...definition,
      targetSampleCount: scenarioTargetCount,
      reviewedCount: reviewedScenarioCounts[scenarioId] ?? 0,
      missingCount: Math.max(0, scenarioTargetCount - (reviewedScenarioCounts[scenarioId] ?? 0)),
    };
  });
  const slots = scenarios.flatMap((scenario) => makeScenarioSlots(scenario, manifest.collectionPlan.minimumBlindReviewers));
  const reviewedSampleCount = reviewedIphoneCaptureSamples(manifest).length;
  const nextSlot = slots.find((slot) => slot.status === "needed") ?? null;

  return {
    version: "1.0",
    generatedFor: "LensPilot single-phone real iPhone calibration",
    manifestPath,
    status: reviewedSampleCount >= targetRealCaptureCount && slots.every((slot) => slot.status === "reviewed")
      ? "ready"
      : "needs_more_samples",
    summary: {
      targetRealCaptureCount,
      reviewedSampleCount,
      missingSampleCount: Math.max(0, targetRealCaptureCount - reviewedSampleCount),
      scenarioTargetCount,
      minimumBlindReviewers: manifest.collectionPlan.minimumBlindReviewers,
      requiredDomains: manifest.collectionPlan.requiredDomains,
      requiredScenarios,
    },
    privacy: {
      singlePhoneOnly: true,
      requiresSecondPhone: false,
      storesRawPhotos: false,
      uploadsLiveCameraFrames: false,
      uploadsPrivateReferencePhotos: false,
      uploadsIdentityData: false,
      usesCloudAnalysisForCalibration: false,
      allowsGenerativeEditsForCalibration: false,
      optionalOnlineInspirationUsesPromptSummariesOnly: true,
    },
    commands: {
      readiness: "npm run calibration:readiness",
      sessionPlan: "npm run calibration:session-plan",
      importReviewed: "npm run calibration:import-reviewed -- --sample <reviewed-sample.json> --write",
      validate: "npm run validate",
    },
    collectionSteps: [
      "Run this plan from shared/typescript before the field session.",
      "On the same iPhone, open the LensPilot camera and select the next needed calibration scenario.",
      "Confirm the reference photo appears as the on-screen popup when a private or public reference is selected.",
      "Tap the popup to verify the full same-phone reference viewer opens, then return to the camera.",
      "Capture the guided burst on the same phone and keep only the selected real result for review.",
      "Use the in-app blind review sheet to add labels without showing Target Match scores.",
      "Share the reviewed iphone_capture JSON back to the repo machine and import it with the reviewed-sample command.",
    ],
    reviewRules: [
      "Use at least two blind reviewers or two independent blind-review passes.",
      "Do not include names, contacts, identity labels, raw photos, EXIF GPS, live frames, or private reference images in reviewed JSON.",
      "Keep privacy.singlePhoneOnly true and cloudAnalysisUsed, generativeEditsAllowed, and identityRecognitionAllowed false.",
      "Optional online inspiration can guide the shoot only through consented public-source summaries; it must not be embedded in calibration exports.",
    ],
    domains: manifest.collectionPlan.requiredDomains.map((domain) => ({
      id: domain,
      reviewedCount: reviewedDomainCounts[domain] ?? 0,
      targetCount: scenarios
        .filter((scenario) => scenario.domain === domain)
        .reduce((sum, scenario) => sum + scenario.targetSampleCount, 0),
    })),
    scenarios,
    slots,
    nextSlot,
  };
}

function makeScenarioSlots(scenario, minimumBlindReviewers) {
  return Array.from({ length: scenario.targetSampleCount }, (_, index) => {
    const slotNumber = index + 1;
    const status = index < scenario.reviewedCount ? "reviewed" : "needed";
    const slotId = `${scenario.id}_${String(slotNumber).padStart(2, "0")}`;

    return {
      id: slotId,
      scenarioId: scenario.id,
      scenarioTitle: scenario.title,
      domain: scenario.domain,
      status,
      prompt: scenario.prompt,
      fieldGoal: scenario.fieldGoal,
      captureTip: scenario.captureTip,
      minimumBlindReviewers,
      suggestedReviewedFileName: `iphone_capture_${slotId}.reviewed.json`,
      importCommand: "npm run calibration:import-reviewed -- --sample <reviewed-sample.json> --write",
      singlePhoneChecks: [
        "camera preview stayed on this phone",
        "reference popup opened on this phone when selected",
        "full reference viewer opened from the popup on this phone",
        "capture, ranking, blind review, and export happened on this phone",
      ],
    };
  });
}

function reviewedIphoneCaptureSamples(manifest) {
  return (manifest.samples ?? []).filter((sample) => sample.sampleKind === "iphone_capture");
}

function reviewedCountsByScenario(manifest, requiredScenarios) {
  const counts = Object.fromEntries(requiredScenarios.map((scenarioId) => [scenarioId, 0]));

  for (const sample of reviewedIphoneCaptureSamples(manifest)) {
    const scenarioId = sample.captureMetadata?.calibrationScenarioId;
    if (!Object.hasOwn(counts, scenarioId)) continue;
    const scenario = scenarioDefinitions[scenarioId];
    if (!scenario || sample.domain !== scenario.domain) continue;
    counts[scenarioId] += 1;
  }

  return counts;
}

function reviewedCountsByDomain(manifest, requiredDomains) {
  const counts = Object.fromEntries(requiredDomains.map((domain) => [domain, 0]));

  for (const sample of reviewedIphoneCaptureSamples(manifest)) {
    if (Object.hasOwn(counts, sample.domain)) {
      counts[sample.domain] += 1;
    }
  }

  return counts;
}

function formatMarkdown(plan) {
  const lines = [
    "# LensPilot Single-Phone Calibration Session",
    "",
    `Status: ${plan.status}`,
    `Reviewed captures: ${plan.summary.reviewedSampleCount}/${plan.summary.targetRealCaptureCount}`,
    `Missing captures: ${plan.summary.missingSampleCount}`,
    `Single phone only: ${plan.privacy.singlePhoneOnly ? "yes" : "no"}`,
    "",
    "## Commands",
    "",
    "Run from `shared/typescript`:",
    "",
    `- \`${plan.commands.sessionPlan}\``,
    `- \`${plan.commands.readiness}\``,
    `- \`${plan.commands.importReviewed}\``,
    `- \`${plan.commands.validate}\``,
    "",
    "## Field Rules",
    "",
    ...plan.collectionSteps.map((step) => `- ${step}`),
    "",
    "## Review Rules",
    "",
    ...plan.reviewRules.map((rule) => `- ${rule}`),
    "",
    "## Domain Targets",
    "",
    "| Domain | Reviewed | Target |",
    "| --- | ---: | ---: |",
    ...plan.domains.map((domain) => `| ${domain.id} | ${domain.reviewedCount} | ${domain.targetCount} |`),
    "",
    "## Capture Slots",
    "",
    "| Slot | Scenario | Domain | Status | Prompt | File hint |",
    "| --- | --- | --- | --- | --- | --- |",
    ...plan.slots.map((slot) => [
      `| ${slot.id}`,
      slot.scenarioTitle,
      slot.domain,
      slot.status,
      escapeMarkdownTableCell(slot.prompt),
      `\`${slot.suggestedReviewedFileName}\` |`,
    ].join(" | ")),
  ];

  if (plan.nextSlot) {
    lines.push(
      "",
      `Next capture: ${plan.nextSlot.scenarioTitle}`,
      `Prompt: ${plan.nextSlot.prompt}`,
      `Field goal: ${plan.nextSlot.fieldGoal}`,
      `Tip: ${plan.nextSlot.captureTip}`,
    );
  }

  return lines.join("\n");
}

function escapeMarkdownTableCell(value) {
  return String(value).replace(/\|/g, "\\|");
}

function parseArgs(argv) {
  const options = {};

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--help" || arg === "-h") {
      options.help = true;
    } else if (arg === "--json") {
      options.json = true;
    } else if (arg === "--markdown") {
      options.json = false;
    } else if (arg === "--manifest") {
      options.manifestPath = takeValue(argv, ++index, arg);
    } else if (arg === "--out") {
      options.outputPath = takeValue(argv, ++index, arg);
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
  npm run calibration:session-plan -- [--manifest <target-match-calibration.json>] [--json] [--out <path>]

Options:
  --manifest <path>    Calibration manifest to inspect. Defaults to tests/calibration/target-match-calibration.json.
  --json               Print the session plan as JSON for automation.
  --markdown           Print the session plan as Markdown. This is the default.
  --out <path>         Write the plan to a file instead of stdout.
`);
}
