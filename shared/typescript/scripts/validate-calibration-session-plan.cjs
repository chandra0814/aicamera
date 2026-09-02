const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const repoRoot = findRepoRoot();
const scriptPath = path.join(repoRoot, "shared/typescript/scripts/calibration-session-plan.cjs");
const manifest = JSON.parse(fs.readFileSync(path.join(repoRoot, "tests/calibration/target-match-calibration.json"), "utf8"));

const jsonResult = runSessionPlan(["--json"]);
const plan = JSON.parse(jsonResult.stdout);
const expectedScenarioIds = manifest.collectionPlan.requiredScenarios;
const expectedTargetCount = manifest.collectionPlan.realCaptureTargetCount;
const expectedScenarioTargetCount = expectedTargetCount / expectedScenarioIds.length;
const reviewedSamples = (manifest.samples ?? []).filter((sample) => sample.sampleKind === "iphone_capture");
const expectedScenarioCounts = reviewedCountsByScenario(reviewedSamples, expectedScenarioIds);
const expectedDomainCounts = reviewedCountsByDomain(reviewedSamples, manifest.collectionPlan.requiredDomains);
const expectedNextScenarioId = expectedScenarioIds.find((scenarioId) => expectedScenarioCounts[scenarioId] < expectedScenarioTargetCount) ?? null;
const expectedStatus = reviewedSamples.length >= expectedTargetCount && expectedNextScenarioId === null
  ? "ready"
  : "needs_more_samples";

assert(plan.version === "1.0", "Session plan should expose a stable schema version.");
assert(plan.generatedFor === "LensPilot single-phone real iPhone calibration", "Session plan should identify the calibration purpose.");
assert(plan.status === expectedStatus, "Session plan status should match current real-capture coverage.");
assert(plan.summary.reviewedSampleCount === reviewedSamples.length, "Session plan should report current reviewed captures.");
assert(plan.summary.targetRealCaptureCount === expectedTargetCount, "Session plan should match the manifest target count.");
assert(plan.summary.scenarioTargetCount === expectedScenarioTargetCount, "Session plan should divide targets evenly across scenarios.");
assert(plan.summary.minimumBlindReviewers === manifest.collectionPlan.minimumBlindReviewers, "Session plan should expose the blind-review requirement.");
assert(JSON.stringify(plan.summary.requiredScenarios) === JSON.stringify(expectedScenarioIds), "Session plan should preserve manifest scenario order.");
assert(JSON.stringify(plan.scenarios.map((scenario) => scenario.id)) === JSON.stringify(expectedScenarioIds), "Scenario entries should preserve manifest order.");
assert(plan.slots.length === expectedTargetCount, "Session plan should generate one slot per required real capture.");
if (expectedNextScenarioId) {
  assert(plan.nextSlot?.scenarioId === expectedNextScenarioId, "Session plan should recommend the first missing scenario.");
} else {
  assert(plan.nextSlot === null, "Complete session plan should not recommend another capture.");
}
assert(plan.commands.importReviewed.includes("calibration:import-reviewed"), "Session plan should include the reviewed-sample import command.");
assert(plan.commands.readiness === "npm run calibration:readiness", "Session plan should include the readiness command.");
assert(plan.privacy.singlePhoneOnly === true, "Session plan must stay single-phone only.");
assert(plan.privacy.requiresSecondPhone === false, "Session plan must not require a second phone.");
assert(plan.privacy.storesRawPhotos === false, "Session plan must not store raw photos.");
assert(plan.privacy.uploadsLiveCameraFrames === false, "Session plan must not upload live camera frames.");
assert(plan.privacy.uploadsPrivateReferencePhotos === false, "Session plan must not upload private reference photos.");
assert(plan.privacy.usesCloudAnalysisForCalibration === false, "Session plan must not require cloud analysis for calibration.");

for (const scenarioId of expectedScenarioIds) {
  const slots = plan.slots.filter((slot) => slot.scenarioId === scenarioId);
  const reviewedSlotCount = Math.min(expectedScenarioTargetCount, expectedScenarioCounts[scenarioId] ?? 0);
  assert(slots.length === expectedScenarioTargetCount, `${scenarioId} should have three capture slots.`);
  assert(slots.filter((slot) => slot.status === "reviewed").length === reviewedSlotCount, `${scenarioId} reviewed slot count should match imported samples.`);
  assert(slots.filter((slot) => slot.status === "needed").length === expectedScenarioTargetCount - reviewedSlotCount, `${scenarioId} needed slot count should match remaining samples.`);
  assert(slots.every((slot) => slot.singlePhoneChecks.length === 4), `${scenarioId} slots should include same-phone checks.`);
  assert(slots.every((slot) => slot.suggestedReviewedFileName.endsWith(".reviewed.json")), `${scenarioId} slots should provide reviewed JSON file hints.`);
}

const domains = new Set(plan.domains.map((domain) => domain.id));
for (const domain of manifest.collectionPlan.requiredDomains) {
  assert(domains.has(domain), `Session plan should include domain ${domain}.`);
  const planDomain = plan.domains.find((entry) => entry.id === domain);
  assert(planDomain.reviewedCount === (expectedDomainCounts[domain] ?? 0), `Session plan should report reviewed count for ${domain}.`);
}

const markdownResult = runSessionPlan([]);
assert(markdownResult.stdout.includes("# LensPilot Single-Phone Calibration Session"), "Markdown plan should include a title.");
assert(markdownResult.stdout.includes("Single phone only: yes"), "Markdown plan should call out single-phone operation.");
assert(markdownResult.stdout.includes("## Capture Slots"), "Markdown plan should list capture slots.");
if (expectedNextScenarioId) {
  assert(markdownResult.stdout.includes("Next capture:"), "Markdown plan should expose the next capture.");
}
assert(!markdownResult.stdout.includes("OPENAI_API_KEY"), "Markdown plan must not mention OpenAI secrets.");
assert(!markdownResult.stdout.includes("LENSPILOT_CREATIVE_API_TOKEN"), "Markdown plan must not mention phone bearer token values.");
assert(!markdownResult.stdout.includes("LENSPILOT_CLIENT_SIGNING_SECRET"), "Markdown plan must not mention signing secrets.");

const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "lenspilot-session-plan-"));
try {
  const outputPath = path.join(tempDir, "field-session.md");
  const writeResult = runSessionPlan(["--out", outputPath]);
  assert(writeResult.stderr.includes("Wrote LensPilot calibration session plan"), "Session plan should report safe write metadata.");
  assert(fs.readFileSync(outputPath, "utf8").includes("## Field Rules"), "Session plan should write Markdown output to disk.");
} finally {
  fs.rmSync(tempDir, { recursive: true, force: true });
}

console.log(JSON.stringify({
  calibrationSessionPlan: true,
  slots: plan.slots.length,
  scenarios: plan.scenarios.map((scenario) => scenario.id),
  nextSlot: plan.nextSlot?.id ?? null,
  status: "passed",
}, null, 2));

function reviewedCountsByScenario(samples, expectedScenarioIds) {
  const counts = Object.fromEntries(expectedScenarioIds.map((scenarioId) => [scenarioId, 0]));

  for (const sample of samples) {
    const scenarioId = sample.captureMetadata?.calibrationScenarioId;
    if (Object.hasOwn(counts, scenarioId)) {
      counts[scenarioId] += 1;
    }
  }

  return counts;
}

function reviewedCountsByDomain(samples, expectedDomains) {
  const counts = Object.fromEntries(expectedDomains.map((domain) => [domain, 0]));

  for (const sample of samples) {
    if (Object.hasOwn(counts, sample.domain)) {
      counts[sample.domain] += 1;
    }
  }

  return counts;
}

function runSessionPlan(args) {
  const result = spawnSync(process.execPath, [
    "-e",
    `globalThis.__LENSPILOT_RUN_SESSION_PLAN_CLI__ = true; const fs = require("node:fs"); eval(fs.readFileSync(${JSON.stringify(scriptPath)}, "utf8"));`,
    "--",
    ...args,
  ], {
    cwd: path.join(repoRoot, "shared/typescript"),
    encoding: "utf8",
  });

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

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}
