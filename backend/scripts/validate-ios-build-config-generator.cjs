const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const scriptDir = fs.existsSync(path.join(__dirname, "generate-ios-build-config.cjs"))
  ? __dirname
  : path.join(process.cwd(), "scripts");
const repoRoot = path.resolve(scriptDir, "..", "..");
const scriptPath = path.join(scriptDir, "generate-ios-build-config.cjs");

const generatorModule = { exports: {} };
const {
  makeLensPilotIOSBuildConfig,
  normalizeCreativeApiURL,
  parseEnvFile,
  run,
} = Function(
  "module",
  "exports",
  "require",
  "__dirname",
  "__filename",
  `${fs.readFileSync(scriptPath, "utf8")}
return module.exports;
`
)(
  generatorModule,
  generatorModule.exports,
  require,
  scriptDir,
  scriptPath
);

const fixtureSecrets = {
  phoneToken: "lp_phone_1234567890123456789012345678901234567890123",
  signingSecret: "lp_signing_1234567890123456789012345678901234567890123",
  metricsToken: "lp_metrics_1234567890123456789012345678901234567890123",
  openAIKey: "sk-test_should_not_be_exported",
};

const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "lenspilot-ios-config-"));
const fixtureEnvPath = path.join(tempRoot, "production.env");
const fixtureOutputPath = path.join(tempRoot, "LensPilotSecrets.generated.xcconfig");

fs.writeFileSync(
  fixtureEnvPath,
  [
    `OPENAI_API_KEY=${fixtureSecrets.openAIKey}`,
    "LENSPILOT_CREATIVE_API_URL=",
    `LENSPILOT_CREATIVE_API_TOKEN=${fixtureSecrets.phoneToken}`,
    `LENSPILOT_CLIENT_SIGNING_SECRET=${fixtureSecrets.signingSecret}`,
    `LENSPILOT_METRICS_TOKEN=${fixtureSecrets.metricsToken}`,
    "",
  ].join("\n"),
  "utf8"
);

const entries = parseEnvFile(fs.readFileSync(fixtureEnvPath, "utf8"));
const directConfig = makeLensPilotIOSBuildConfig({
  entries,
  creativeApiURL: "https://api.lenspilot.example",
});
assertIncludes(
  directConfig.source,
  "LENSPILOT_CREATIVE_API_URL = https:$(SLASH)$(SLASH)api.lenspilot.example$(SLASH)v1$(SLASH)creative-interpretation",
  "Generated iOS config should normalize and Xcode-escape the Creative API route."
);
assertIncludes(
  directConfig.source,
  `LENSPILOT_CREATIVE_API_TOKEN = ${fixtureSecrets.phoneToken}`,
  "Generated iOS config should include only the phone bearer token."
);
assertIncludes(
  directConfig.source,
  `LENSPILOT_CREATIVE_API_SIGNING_SECRET = ${fixtureSecrets.signingSecret}`,
  "Generated iOS config should mirror the phone signing secret."
);
assertDoesNotInclude(directConfig.source, "OPENAI_API_KEY", "iOS config must never include the OpenAI key name.");
assertDoesNotInclude(directConfig.source, fixtureSecrets.openAIKey, "iOS config must never include the OpenAI key value.");
assertDoesNotInclude(directConfig.source, "LENSPILOT_METRICS_TOKEN", "iOS config must never include the metrics token name.");
assertDoesNotInclude(directConfig.source, fixtureSecrets.metricsToken, "iOS config must never include the metrics token value.");

assert(
  normalizeCreativeApiURL("https://api.lenspilot.example/v1/creative-interpretation?debug=true#frag")
    === "https://api.lenspilot.example/v1/creative-interpretation",
  "Creative API URL normalization should remove query strings and fragments."
);
assertThrows(
  () => normalizeCreativeApiURL("http://api.lenspilot.example/v1/creative-interpretation"),
  "creative_api_url_must_use_https",
  "Production Creative API URLs must use HTTPS."
);
assertThrows(
  () => normalizeCreativeApiURL("https://user:pass@api.lenspilot.example/v1/creative-interpretation"),
  "creative_api_url_must_not_include_credentials",
  "Creative API URLs must not carry credentials."
);
assertThrows(
  () => normalizeCreativeApiURL("https://api.lenspilot.example/v1/other"),
  "creative_api_url_must_target_creative_interpretation_route",
  "Creative API URLs must target the creative-interpretation route."
);

let cliStdout = "";
let cliStderr = "";
const originalConsoleLog = console.log;
const originalConsoleError = console.error;
try {
  console.log = (value) => {
    cliStdout += `${value}\n`;
  };
  console.error = (value) => {
    cliStderr += `${value}\n`;
  };
  run(
    [
      "--env-file",
      fixtureEnvPath,
      "--creative-api-url",
      "https://api.lenspilot.example",
      "--output",
      fixtureOutputPath,
    ],
    { environment: {} }
  );
} finally {
  console.log = originalConsoleLog;
  console.error = originalConsoleError;
}

const cliCombinedOutput = `${cliStdout}\n${cliStderr}`;
assertIncludes(cliStdout, '"secretValuesPrinted": false', "CLI should report that secret values were not printed.");
for (const secretValue of Object.values(fixtureSecrets)) {
  assertDoesNotInclude(cliCombinedOutput, secretValue, "CLI output must not include secret values.");
}
const generatedSource = fs.readFileSync(fixtureOutputPath, "utf8");
assert(generatedSource === directConfig.source, "CLI should write the same safe iOS config source as the generator.");

const gitignore = fs.readFileSync(path.join(repoRoot, ".gitignore"), "utf8");
assertIncludes(
  gitignore,
  "ios/App/LensPilotApp/Config/*.generated.xcconfig",
  "Generated iOS build configs should be ignored by git."
);

const trackedConfig = fs.readFileSync(
  path.join(repoRoot, "ios", "App", "LensPilotApp", "Config", "LensPilotConfig.xcconfig"),
  "utf8"
);
assertIncludes(
  trackedConfig,
  '#include? "LensPilotSecrets.generated.xcconfig"',
  "Tracked iOS config should optionally include local generated secrets."
);
assertDoesNotInclude(trackedConfig, "lp_phone_", "Tracked iOS config should not contain a phone token.");
assertDoesNotInclude(trackedConfig, "lp_signing_", "Tracked iOS config should not contain a signing secret.");
assertDoesNotInclude(trackedConfig, "https://lenspilot-creative-api.onrender.com", "Tracked iOS config should not hard-code production host values.");

const projectFile = fs.readFileSync(
  path.join(repoRoot, "ios", "App", "LensPilotApp", "LensPilotApp.xcodeproj", "project.pbxproj"),
  "utf8"
);
assertIncludes(projectFile, "LensPilotConfig.xcconfig", "Xcode project should reference the tracked LensPilot config.");
assert(
  (projectFile.match(/baseConfigurationReference = 202020202020202020202010/g) ?? []).length === 2,
  "Debug and Release app configurations should use the tracked LensPilot config."
);

console.log(JSON.stringify({
  iosBuildConfigGenerator: true,
  routeNormalized: true,
  xcodeConfigOptionalSecrets: true,
  openAIAPIKeyIncluded: false,
  metricsTokenIncluded: false,
  secretValuesPrinted: false,
  status: "passed",
}, null, 2));

function assertIncludes(source, snippet, message) {
  assert(source.includes(snippet), message);
}

function assertDoesNotInclude(source, snippet, message) {
  assert(!source.includes(snippet), message);
}

function assertThrows(fn, expectedMessage, message) {
  try {
    fn();
  } catch (error) {
    assert(error?.message === expectedMessage, `${message} Expected ${expectedMessage}, got ${error?.message}.`);
    return;
  }
  throw new Error(`${message} Expected an error.`);
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}
