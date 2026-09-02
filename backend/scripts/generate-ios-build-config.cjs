const fs = require("node:fs");
const path = require("node:path");

const creativeApiRoutePath = "/v1/creative-interpretation";
const repoRoot = path.resolve(__dirname, "..", "..");
const defaultEnvFilePath = path.join(repoRoot, "backend", ".env.production.generated");
const defaultOutputPath = path.join(
  repoRoot,
  "ios",
  "App",
  "LensPilotApp",
  "Config",
  "LensPilotSecrets.generated.xcconfig"
);

const iosBuildSettingNames = [
  "LENSPILOT_CREATIVE_API_URL",
  "LENSPILOT_CREATIVE_API_TOKEN",
  "LENSPILOT_CREATIVE_API_SIGNING_SECRET",
];

const excludedServerOnlyEnvNames = [
  "OPENAI_API_KEY",
  "RENDER_DEPLOY_HOOK_URL",
  "LENSPILOT_METRICS_TOKEN",
];

function run(argv = process.argv.slice(2), options = {}) {
  const args = parseArgs(argv);
  const envFilePath = path.resolve(args.envFilePath ?? defaultEnvFilePath);
  const outputPath = path.resolve(args.outputPath ?? defaultOutputPath);
  const environment = options.environment ?? process.env;
  const entries = parseEnvFile(fs.readFileSync(envFilePath, "utf8"));
  const config = makeLensPilotIOSBuildConfig({
    entries: {
      ...entries,
      ...pickEnvironmentOverrides(environment),
    },
    creativeApiURL: args.creativeApiURL,
  });

  if (!args.dryRun) {
    fs.mkdirSync(path.dirname(outputPath), { recursive: true });
    fs.writeFileSync(outputPath, config.source, {
      encoding: "utf8",
      flag: args.force ? "w" : "wx",
    });
  }

  console.log(JSON.stringify({
    iosBuildConfigGenerated: !args.dryRun,
    dryRun: args.dryRun,
    path: outputPath,
    envFilePath,
    buildSettingNames: iosBuildSettingNames,
    excludedServerOnlyEnvNames,
    creativeApiRoutePath,
    openAIAPIKeyIncluded: false,
    renderDeployHookIncluded: false,
    metricsTokenIncluded: false,
    secretValuesPrinted: false,
    status: args.dryRun ? "validated" : "written",
  }, null, 2));
}

function makeLensPilotIOSBuildConfig(options = {}) {
  const entries = options.entries ?? {};
  const creativeApiURL = normalizeCreativeApiURL(
    options.creativeApiURL ?? entries.LENSPILOT_CREATIVE_API_URL
  );
  const phoneToken = requireSafeXcconfigValue(
    entries.LENSPILOT_CREATIVE_API_TOKEN,
    "missing_ios_phone_token"
  );
  const signingSecret = requireSafeXcconfigValue(
    entries.LENSPILOT_CREATIVE_API_SIGNING_SECRET || entries.LENSPILOT_CLIENT_SIGNING_SECRET,
    "missing_ios_signing_secret"
  );

  return {
    source: [
      "SLASH = /",
      `LENSPILOT_CREATIVE_API_URL = ${escapeXcconfigURL(creativeApiURL)}`,
      `LENSPILOT_CREATIVE_API_TOKEN = ${phoneToken}`,
      `LENSPILOT_CREATIVE_API_SIGNING_SECRET = ${signingSecret}`,
      "",
    ].join("\n"),
    creativeApiURL,
    buildSettingNames: iosBuildSettingNames,
  };
}

function normalizeCreativeApiURL(value) {
  const cleaned = requireSafeURLString(value, "missing_creative_api_url");
  let url;
  try {
    url = new URL(cleaned);
  } catch {
    throw new Error("invalid_creative_api_url");
  }

  if (url.username || url.password) {
    throw new Error("creative_api_url_must_not_include_credentials");
  }

  const host = url.hostname.toLowerCase();
  const isLocalHost = ["localhost", "127.0.0.1", "::1"].includes(host);
  if (url.protocol !== "https:" && !isLocalHost) {
    throw new Error("creative_api_url_must_use_https");
  }

  const normalizedPath = url.pathname.replace(/\/+$/, "");
  if (normalizedPath === "" || normalizedPath === "/") {
    url.pathname = creativeApiRoutePath;
  } else if (normalizedPath !== creativeApiRoutePath) {
    throw new Error("creative_api_url_must_target_creative_interpretation_route");
  }

  url.search = "";
  url.hash = "";
  return url.toString();
}

function escapeXcconfigURL(value) {
  return value.replace(/\//g, "$(SLASH)");
}

function parseEnvFile(source) {
  const entries = {};
  for (const line of source.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const separatorIndex = line.indexOf("=");
    if (separatorIndex === -1) continue;
    const key = line.slice(0, separatorIndex).trim();
    const value = line.slice(separatorIndex + 1).trim();
    if (key) entries[key] = unquoteEnvValue(value);
  }
  return entries;
}

function unquoteEnvValue(value) {
  if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
    return value.slice(1, -1);
  }
  return value;
}

function pickEnvironmentOverrides(environment) {
  const overrides = {};
  for (const key of [
    "LENSPILOT_CREATIVE_API_URL",
    "LENSPILOT_CREATIVE_API_TOKEN",
    "LENSPILOT_CREATIVE_API_SIGNING_SECRET",
    "LENSPILOT_CLIENT_SIGNING_SECRET",
  ]) {
    if (environment[key]) overrides[key] = environment[key];
  }
  return overrides;
}

function requireSafeURLString(value, errorCode) {
  const cleaned = String(value ?? "").trim();
  if (!cleaned) throw new Error(errorCode);
  if (/[\r\n]/.test(cleaned)) throw new Error("invalid_multiline_creative_api_url");
  return cleaned;
}

function requireSafeXcconfigValue(value, errorCode) {
  const cleaned = String(value ?? "").trim();
  if (!cleaned) throw new Error(errorCode);
  if (!/^[A-Za-z0-9._~:-]+$/.test(cleaned)) {
    throw new Error("unsafe_ios_build_setting_value");
  }
  return cleaned;
}

function parseArgs(argv) {
  const args = {
    creativeApiURL: undefined,
    dryRun: false,
    envFilePath: undefined,
    force: false,
    outputPath: undefined,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const item = argv[index];
    if (item === "--creative-api-url") {
      args.creativeApiURL = readNextArg(argv, index, "missing_creative_api_url");
      index += 1;
    } else if (item === "--dry-run") {
      args.dryRun = true;
    } else if (item === "--env-file") {
      args.envFilePath = readNextArg(argv, index, "missing_env_file_path");
      index += 1;
    } else if (item === "--force") {
      args.force = true;
    } else if (item === "--output") {
      args.outputPath = readNextArg(argv, index, "missing_output_path");
      index += 1;
    } else {
      throw new Error(`unknown_argument_${item.replace(/[^a-z0-9_-]/gi, "_")}`);
    }
  }

  return args;
}

function readNextArg(argv, index, errorCode) {
  const next = argv[index + 1];
  if (!next) throw new Error(errorCode);
  return next;
}

if (require.main === module) {
  try {
    run();
  } catch (error) {
    console.error(JSON.stringify({
      iosBuildConfigGenerated: false,
      status: "error",
      error: {
        code: String(error?.message ?? "ios_build_config_generation_failed")
          .replace(/[^a-z0-9_]/gi, "_")
          .toLowerCase()
          .slice(0, 80),
        message: "LensPilot iOS build config could not be generated.",
      },
    }, null, 2));
    process.exitCode = 1;
  }
}

module.exports = {
  creativeApiRoutePath,
  defaultEnvFilePath,
  defaultOutputPath,
  escapeXcconfigURL,
  excludedServerOnlyEnvNames,
  iosBuildSettingNames,
  makeLensPilotIOSBuildConfig,
  normalizeCreativeApiURL,
  parseEnvFile,
  run,
};
