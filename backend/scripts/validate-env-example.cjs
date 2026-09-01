const fs = require("node:fs");
const path = require("node:path");

const repoRoot = findRepoRoot();
const envExamplePath = path.join(repoRoot, ".env.example");
const envExample = parseEnvExample(fs.readFileSync(envExamplePath, "utf8"));

const requiredKeys = [
  "OPENAI_API_KEY",
  "LENSPILOT_OPENAI_MODEL",
  "LENSPILOT_OPENAI_WEB_SEARCH",
  "LENSPILOT_API_HOST",
  "PORT",
  "LENSPILOT_API_PORT",
  "LENSPILOT_ALLOWED_ORIGINS",
  "LENSPILOT_MAX_REQUEST_BYTES",
  "LENSPILOT_RATE_LIMIT_WINDOW_MS",
  "LENSPILOT_RATE_LIMIT_MAX",
  "LENSPILOT_ENABLE_METRICS",
  "LENSPILOT_METRICS_TOKEN",
  "LENSPILOT_MAX_METRIC_EVENTS",
  "LENSPILOT_REQUIRE_PRODUCTION_SAFETY",
  "LENSPILOT_ENDPOINT_CHECK_TIMEOUT_MS",
  "LENSPILOT_CREATIVE_API_TOKEN",
  "LENSPILOT_CLIENT_SIGNING_SECRET",
  "LENSPILOT_REQUIRE_SIGNED_PHONE_REQUESTS",
  "LENSPILOT_SIGNATURE_TOLERANCE_MS",
  "LENSPILOT_SIGNATURE_REPLAY_MAX_ENTRIES",
  "LENSPILOT_CREATIVE_API_URL",
  "LENSPILOT_CREATIVE_API_SIGNING_SECRET",
  "LENSPILOT_ALLOW_DIRECT_OPENAI_PROVIDER",
];

for (const key of requiredKeys) {
  assert(envExample.has(key), `.env.example is missing ${key}.`);
}

assert(envExample.get("OPENAI_API_KEY") === "", "OPENAI_API_KEY must stay blank in .env.example.");
assert(envExample.get("LENSPILOT_CREATIVE_API_TOKEN") === "", "Phone bearer token must stay blank in .env.example.");
assert(envExample.get("LENSPILOT_CLIENT_SIGNING_SECRET") === "", "Backend signing secret must stay blank in .env.example.");
assert(envExample.get("LENSPILOT_CREATIVE_API_SIGNING_SECRET") === "", "iOS signing secret must stay blank in .env.example.");
assert(envExample.get("LENSPILOT_METRICS_TOKEN") === "", "Metrics token must stay blank in .env.example.");
assert(envExample.get("LENSPILOT_REQUIRE_SIGNED_PHONE_REQUESTS") === "false", "Generic local template should not require signed requests by default.");
assert(envExample.get("LENSPILOT_REQUIRE_PRODUCTION_SAFETY") === "false", "Generic local template should not enforce production safety by default.");
assert(envExample.get("LENSPILOT_ALLOW_DIRECT_OPENAI_PROVIDER") === "false", "Direct iOS OpenAI provider must be disabled by default.");
assert(envExample.get("LENSPILOT_CREATIVE_API_URL").endsWith("/v1/creative-interpretation"), "iOS Creative API URL must include the full route path.");
assert(readPositiveInteger("LENSPILOT_MAX_REQUEST_BYTES") <= 65536, "Request body cap must stay production-safe.");
assert(readPositiveInteger("LENSPILOT_RATE_LIMIT_WINDOW_MS") > 0, "Rate-limit window must be positive.");
assert(readPositiveInteger("LENSPILOT_RATE_LIMIT_MAX") <= 120, "Rate-limit max must stay production-safe.");
assert(readPositiveInteger("LENSPILOT_SIGNATURE_TOLERANCE_MS") <= 300000, "Signature tolerance should not exceed five minutes.");
assert(readPositiveInteger("LENSPILOT_SIGNATURE_REPLAY_MAX_ENTRIES") <= 1000, "Replay cache example should stay bounded.");
assert(readPositiveInteger("LENSPILOT_MAX_METRIC_EVENTS") <= 500, "Metric event retention example should stay bounded.");
assert(readPositiveInteger("LENSPILOT_ENDPOINT_CHECK_TIMEOUT_MS") <= 30000, "Endpoint check timeout example should stay bounded.");

const secretLookingValues = [...envExample.entries()]
  .filter(([, value]) => /sk-[A-Za-z0-9_-]+|sk-proj-[A-Za-z0-9_-]+|client-token|metrics-token|signing-secret/i.test(value));
assert(secretLookingValues.length === 0, ".env.example must not contain secret-looking sample values.");

console.log(JSON.stringify({
  envExample: true,
  requiredKeys: requiredKeys.length,
  productionSafeDefaults: true,
  status: "passed",
}, null, 2));

function readPositiveInteger(key) {
  const value = Number.parseInt(envExample.get(key), 10);
  assert(Number.isFinite(value) && value > 0, `${key} must be a positive integer.`);
  return value;
}

function parseEnvExample(source) {
  const values = new Map();
  for (const [index, rawLine] of source.split(/\r?\n/).entries()) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;

    const match = /^([A-Z0-9_]+)=(.*)$/.exec(line);
    assert(match, `.env.example line ${index + 1} is not KEY=value.`);
    const [, key, value] = match;
    assert(!values.has(key), `.env.example defines ${key} more than once.`);
    values.set(key, value);
  }
  return values;
}

function findRepoRoot() {
  const candidates = [
    path.resolve(process.cwd(), ".."),
    path.resolve(__dirname, "..", ".."),
    process.cwd(),
  ];
  const repoRoot = candidates.find((candidate) => fs.existsSync(path.join(candidate, ".env.example")));
  assert(repoRoot, "Could not locate repository root for .env.example validation.");
  return repoRoot;
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}
