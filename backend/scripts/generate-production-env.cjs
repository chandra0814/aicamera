const fs = require("node:fs");
const path = require("node:path");
const { randomBytes } = require("node:crypto");

const defaultOutputPath = path.resolve(__dirname, "..", ".env.production.generated");

const productionEnvNames = [
  "OPENAI_API_KEY",
  "LENSPILOT_ALLOWED_ORIGINS",
  "LENSPILOT_OPENAI_MODEL",
  "LENSPILOT_OPENAI_WEB_SEARCH",
  "LENSPILOT_MAX_REQUEST_BYTES",
  "LENSPILOT_RATE_LIMIT_WINDOW_MS",
  "LENSPILOT_RATE_LIMIT_MAX",
  "LENSPILOT_ENABLE_METRICS",
  "LENSPILOT_MAX_METRIC_EVENTS",
  "LENSPILOT_REQUIRE_PRODUCTION_SAFETY",
  "LENSPILOT_REQUIRE_SIGNED_PHONE_REQUESTS",
  "LENSPILOT_SIGNATURE_TOLERANCE_MS",
  "LENSPILOT_SIGNATURE_REPLAY_MAX_ENTRIES",
  "LENSPILOT_SECRET_ROTATION_MAX_AGE_DAYS",
  "LENSPILOT_CREATIVE_API_TOKEN",
  "LENSPILOT_CLIENT_SIGNING_SECRET",
  "LENSPILOT_METRICS_TOKEN",
  "LENSPILOT_OPENAI_KEY_ROTATED_AT",
  "LENSPILOT_CREATIVE_API_TOKEN_ROTATED_AT",
  "LENSPILOT_CLIENT_SIGNING_SECRET_ROTATED_AT",
  "LENSPILOT_METRICS_TOKEN_ROTATED_AT",
  "RENDER_DEPLOY_HOOK_URL",
  "LENSPILOT_CREATIVE_API_URL",
  "LENSPILOT_CREATIVE_API_SIGNING_SECRET",
];

function generateSecret(prefix) {
  return `lp_${prefix}_${randomBytes(32).toString("base64url")}`;
}

function makeLensPilotProductionEnvTemplate(options = {}) {
  const generatedAt = toISOString(options.generatedAt ?? new Date());
  const secrets = options.secrets ?? {};
  const phoneToken = secrets.phoneToken ?? generateSecret("phone");
  const signingSecret = secrets.signingSecret ?? generateSecret("signing");
  const metricsToken = secrets.metricsToken ?? generateSecret("metrics");

  return [
    "# LensPilot Creative API production values",
    `# Generated at ${generatedAt}`,
    "# Keep this file local. Copy the values into Render, GitHub Actions secrets, and iOS build settings as needed.",
    "",
    "# Render service environment",
    "OPENAI_API_KEY=",
    "LENSPILOT_ALLOWED_ORIGINS=",
    "LENSPILOT_OPENAI_MODEL=gpt-5.6-luna",
    "LENSPILOT_OPENAI_WEB_SEARCH=true",
    "LENSPILOT_MAX_REQUEST_BYTES=65536",
    "LENSPILOT_RATE_LIMIT_WINDOW_MS=60000",
    "LENSPILOT_RATE_LIMIT_MAX=30",
    "LENSPILOT_ENABLE_METRICS=true",
    "LENSPILOT_MAX_METRIC_EVENTS=100",
    "LENSPILOT_REQUIRE_PRODUCTION_SAFETY=true",
    "LENSPILOT_REQUIRE_SIGNED_PHONE_REQUESTS=true",
    "LENSPILOT_SIGNATURE_TOLERANCE_MS=300000",
    "LENSPILOT_SIGNATURE_REPLAY_MAX_ENTRIES=1000",
    "LENSPILOT_SECRET_ROTATION_MAX_AGE_DAYS=90",
    `LENSPILOT_CREATIVE_API_TOKEN=${phoneToken}`,
    `LENSPILOT_CLIENT_SIGNING_SECRET=${signingSecret}`,
    `LENSPILOT_METRICS_TOKEN=${metricsToken}`,
    `LENSPILOT_OPENAI_KEY_ROTATED_AT=${generatedAt}`,
    `LENSPILOT_CREATIVE_API_TOKEN_ROTATED_AT=${generatedAt}`,
    `LENSPILOT_CLIENT_SIGNING_SECRET_ROTATED_AT=${generatedAt}`,
    `LENSPILOT_METRICS_TOKEN_ROTATED_AT=${generatedAt}`,
    "",
    "# GitHub Actions secrets",
    "RENDER_DEPLOY_HOOK_URL=",
    "LENSPILOT_CREATIVE_API_URL=",
    `LENSPILOT_METRICS_TOKEN=${metricsToken}`,
    "",
    "# iOS build settings",
    "LENSPILOT_CREATIVE_API_URL=",
    `LENSPILOT_CREATIVE_API_TOKEN=${phoneToken}`,
    `LENSPILOT_CREATIVE_API_SIGNING_SECRET=${signingSecret}`,
    "",
  ].join("\n");
}

function run(argv = process.argv.slice(2)) {
  const args = parseArgs(argv);
  const targetPath = path.resolve(args.outputPath ?? defaultOutputPath);
  const content = makeLensPilotProductionEnvTemplate();

  fs.mkdirSync(path.dirname(targetPath), { recursive: true });
  fs.writeFileSync(targetPath, content, {
    encoding: "utf8",
    flag: args.force ? "w" : "wx",
  });

  console.log(JSON.stringify({
    productionEnvGenerated: true,
    path: targetPath,
    envNames: productionEnvNames,
    generatedSecretNames: [
      "LENSPILOT_CREATIVE_API_TOKEN",
      "LENSPILOT_CLIENT_SIGNING_SECRET",
      "LENSPILOT_METRICS_TOKEN",
      "LENSPILOT_CREATIVE_API_SIGNING_SECRET",
    ],
    openAIAPIKeyIncluded: false,
    status: "written",
  }, null, 2));
}

function parseArgs(argv) {
  const args = {
    force: false,
    outputPath: undefined,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const item = argv[index];
    if (item === "--force") {
      args.force = true;
    } else if (item === "--output") {
      const next = argv[index + 1];
      if (!next) throw new Error("missing_output_path");
      args.outputPath = next;
      index += 1;
    } else {
      throw new Error(`unknown_argument_${item.replace(/[^a-z0-9_-]/gi, "_")}`);
    }
  }
  return args;
}

function toISOString(value) {
  const date = value instanceof Date ? value : new Date(value);
  if (!Number.isFinite(date.getTime())) throw new Error("invalid_generation_date");
  return date.toISOString();
}

if (require.main === module) {
  try {
    run();
  } catch (error) {
    console.error(JSON.stringify({
      productionEnvGenerated: false,
      status: "error",
      error: {
        code: String(error?.message ?? "production_env_generation_failed")
          .replace(/[^a-z0-9_]/gi, "_")
          .toLowerCase()
          .slice(0, 80),
        message: "LensPilot production env file could not be generated.",
      },
    }, null, 2));
    process.exitCode = 1;
  }
}

module.exports = {
  defaultOutputPath,
  generateSecret,
  makeLensPilotProductionEnvTemplate,
  productionEnvNames,
  run,
};
