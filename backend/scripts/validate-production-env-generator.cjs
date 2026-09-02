const fs = require("node:fs");
const path = require("node:path");

const generatorModule = { exports: {} };
const generatorExports = Function(
  "module",
  "exports",
  "require",
  "__dirname",
  "__filename",
  `${fs.readFileSync("scripts/generate-production-env.cjs", "utf8")}
return module.exports;
`
)(
  generatorModule,
  generatorModule.exports,
  require,
  path.resolve(process.cwd(), "scripts"),
  path.resolve(process.cwd(), "scripts", "generate-production-env.cjs")
);

const {
  generateSecret,
  makeLensPilotProductionEnvTemplate,
  productionEnvNames,
} = generatorExports;

const fixtureSecrets = {
  phoneToken: "lp_phone_1234567890123456789012345678901234567890123",
  signingSecret: "lp_signing_1234567890123456789012345678901234567890123",
  metricsToken: "lp_metrics_1234567890123456789012345678901234567890123",
};

const source = makeLensPilotProductionEnvTemplate({
  generatedAt: "2026-09-02T00:00:00.000Z",
  secrets: fixtureSecrets,
});
const entries = parseEnvTemplate(source);

for (const envName of productionEnvNames) {
  assert(Object.prototype.hasOwnProperty.call(entries, envName), `${envName} should be present in generated production env template.`);
}

assert(entries.OPENAI_API_KEY === "", "Generated template must not include an OpenAI API key.");
assert(entries.RENDER_DEPLOY_HOOK_URL === "", "Generated template must not include a Render deploy hook URL.");
assert(entries.LENSPILOT_CREATIVE_API_URL === "", "Generated template must not include a deployed API URL.");
assert(entries.LENSPILOT_REQUIRE_PRODUCTION_SAFETY === "true", "Generated template should enable production safety.");
assert(entries.LENSPILOT_REQUIRE_SIGNED_PHONE_REQUESTS === "true", "Generated template should require signed phone requests.");
assert(entries.LENSPILOT_SECRET_ROTATION_MAX_AGE_DAYS === "90", "Generated template should cap secret rotation age at 90 days.");
assert(entries.LENSPILOT_RATE_LIMIT_MAX === "30", "Generated template should keep production rate limits bounded.");
assert(entries.LENSPILOT_METRICS_TOKEN === fixtureSecrets.metricsToken, "Generated template should use the same metrics token across sections.");
assert(entries.LENSPILOT_CREATIVE_API_TOKEN === fixtureSecrets.phoneToken, "Generated template should use the same phone bearer token across sections.");
assert(entries.LENSPILOT_CLIENT_SIGNING_SECRET === fixtureSecrets.signingSecret, "Generated template should include a backend signing secret.");
assert(entries.LENSPILOT_CREATIVE_API_SIGNING_SECRET === fixtureSecrets.signingSecret, "Generated template should mirror the signing secret for iOS.");

for (const rotationKey of [
  "LENSPILOT_OPENAI_KEY_ROTATED_AT",
  "LENSPILOT_CREATIVE_API_TOKEN_ROTATED_AT",
  "LENSPILOT_CLIENT_SIGNING_SECRET_ROTATED_AT",
  "LENSPILOT_METRICS_TOKEN_ROTATED_AT",
]) {
  assert(entries[rotationKey] === "2026-09-02T00:00:00.000Z", `${rotationKey} should use the generation timestamp.`);
}

for (const prefix of ["phone", "signing", "metrics"]) {
  const secret = generateSecret(prefix);
  assert(secret.startsWith(`lp_${prefix}_`), `Generated ${prefix} secret should include a safe prefix.`);
  assert(secret.length >= 40, `Generated ${prefix} secret should have enough entropy text.`);
  assert(/^[A-Za-z0-9_-]+$/.test(secret.replace(`lp_${prefix}_`, "")), `Generated ${prefix} secret should be shell-safe.`);
}

console.log(JSON.stringify({
  productionEnvGenerator: true,
  requiredKeys: productionEnvNames.length,
  secretValuesPrinted: false,
  status: "passed",
}, null, 2));

function parseEnvTemplate(sourceText) {
  const entries = {};
  for (const line of sourceText.split(/\r?\n/)) {
    if (!line || line.trim().startsWith("#")) continue;
    const separatorIndex = line.indexOf("=");
    if (separatorIndex === -1) continue;
    entries[line.slice(0, separatorIndex)] = line.slice(separatorIndex + 1);
  }
  return entries;
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}
