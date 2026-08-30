const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const repoRoot = findRepoRoot();
const scriptPath = path.join(repoRoot, "shared/typescript/scripts/calibration-readiness-report.cjs");

const humanReport = runReadinessReport([]);
assert(humanReport.stdout.includes("Calibration readiness: needs_more_samples"), "Readiness report should show current non-ready status.");
assert(humanReport.stdout.includes("Reviewed captures: 0/24"), "Readiness report should show reviewed capture progress.");
assert(humanReport.stdout.includes("[ ] Portrait (portrait): 0/3"), "Readiness report should list portrait scenario progress.");
assert(humanReport.stdout.includes("Next capture: Portrait"), "Readiness report should recommend the first missing scenario.");

const jsonReport = runReadinessReport(["--json"]);
const report = JSON.parse(jsonReport.stdout);
assert(report.status === "needs_more_samples", "JSON readiness report should expose status.");
assert(report.reviewedSampleCount === 0, "JSON readiness report should expose reviewed sample count.");
assert(report.targetRealCaptureCount === 24, "JSON readiness report should expose target sample count.");
assert(report.domains.length === 4, "JSON readiness report should include all required domains.");
assert(report.scenarios.length === 8, "JSON readiness report should include all required scenarios.");
assert(report.nextScenario?.id === "portrait", "JSON readiness report should expose the next scenario.");
assert(report.validationStatus === "passed", "Readiness report should be based on a valid manifest.");

console.log(JSON.stringify({
  calibrationReadinessReport: true,
  status: report.status,
  nextScenario: report.nextScenario.id,
  checks: {
    domains: report.domains.length,
    scenarios: report.scenarios.length,
  },
}, null, 2));

function runReadinessReport(args) {
  const result = spawnSync(process.execPath, [
    "-e",
    `globalThis.__LENSPILOT_RUN_READINESS_CLI__ = true; const fs = require("node:fs"); eval(fs.readFileSync(${JSON.stringify(scriptPath)}, "utf8"));`,
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
