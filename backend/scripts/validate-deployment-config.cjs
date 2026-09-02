const fs = require("node:fs");
const path = require("node:path");

const repoRoot = findRepoRoot();
const backendRoot = path.join(repoRoot, "backend");

const dockerfile = readText(path.join(backendRoot, "Dockerfile"));
const dockerignore = readText(path.join(backendRoot, ".dockerignore"));
const renderYaml = readText(path.join(repoRoot, "render.yaml"));
const endpointWorkflow = readText(path.join(repoRoot, ".github", "workflows", "lenspilot-production-endpoint-check.yml"));

assertIncludes(dockerfile, "FROM node:20-alpine", "Dockerfile should use the supported Node 20 runtime.");
assertIncludes(dockerfile, "LENSPILOT_API_HOST=0.0.0.0", "Dockerfile should bind the API to the container network interface.");
assertIncludes(dockerfile, "COPY api ./api", "Dockerfile should include the Creative API implementation.");
assertIncludes(dockerfile, "COPY server.mjs ./", "Dockerfile should include the deployable server.");
assertIncludes(dockerfile, "EXPOSE 8787", "Dockerfile should document the default backend port.");
assertIncludes(dockerfile, "HEALTHCHECK", "Dockerfile should expose a container health check.");
assertIncludes(dockerfile, "USER node", "Dockerfile should run as the unprivileged node user.");
assertIncludes(dockerfile, 'CMD ["node", "server.mjs"]', "Dockerfile should start the LensPilot backend directly.");
assert(!/COPY\s+\.env/i.test(dockerfile), "Dockerfile must not copy local env files.");

assertIncludes(dockerignore, ".env.*", ".dockerignore should exclude local env files.");
assertIncludes(dockerignore, "node_modules", ".dockerignore should exclude local node_modules.");

for (const key of [
  "OPENAI_API_KEY",
  "LENSPILOT_ALLOWED_ORIGINS",
  "LENSPILOT_CREATIVE_API_TOKEN",
  "LENSPILOT_CLIENT_SIGNING_SECRET",
  "LENSPILOT_METRICS_TOKEN",
  "LENSPILOT_OPENAI_KEY_ROTATED_AT",
  "LENSPILOT_CREATIVE_API_TOKEN_ROTATED_AT",
  "LENSPILOT_CLIENT_SIGNING_SECRET_ROTATED_AT",
  "LENSPILOT_METRICS_TOKEN_ROTATED_AT",
]) {
  assertSecretEnvVarIsUnsynced(renderYaml, key);
}

for (const line of [
  "runtime: docker",
  "dockerfilePath: ./backend/Dockerfile",
  "dockerContext: ./backend",
  "healthCheckPath: /health",
  "LENSPILOT_REQUIRE_PRODUCTION_SAFETY",
  "LENSPILOT_REQUIRE_SIGNED_PHONE_REQUESTS",
  "LENSPILOT_SECRET_ROTATION_MAX_AGE_DAYS",
]) {
  assertIncludes(renderYaml, line, `render.yaml should include ${line}.`);
}

assertIncludes(endpointWorkflow, "LensPilot Production Endpoint Check", "Production endpoint workflow should be named.");
assertIncludes(endpointWorkflow, "workflow_dispatch", "Production endpoint workflow should be manually runnable.");
assertIncludes(endpointWorkflow, "schedule:", "Production endpoint workflow should run on a schedule.");
assertIncludes(endpointWorkflow, "LENSPILOT_CREATIVE_API_URL", "Production endpoint workflow should require the deployed API URL.");
assertIncludes(endpointWorkflow, "LENSPILOT_METRICS_TOKEN", "Production endpoint workflow should pass the optional metrics token.");
assertIncludes(endpointWorkflow, "npm run check:production-endpoint", "Production endpoint workflow should run the safe endpoint checker.");

console.log(JSON.stringify({
  deploymentConfig: true,
  dockerfile: true,
  renderBlueprint: true,
  productionEndpointWorkflow: true,
  status: "passed",
}, null, 2));

function assertSecretEnvVarIsUnsynced(source, key) {
  const blockPattern = new RegExp(`- key: ${escapeRegExp(key)}\\r?\\n\\s+sync: false`);
  assert(blockPattern.test(source), `${key} should be marked sync: false in render.yaml.`);
}

function assertIncludes(source, snippet, message) {
  assert(source.includes(snippet), message);
}

function readText(filePath) {
  return fs.readFileSync(filePath, "utf8");
}

function findRepoRoot() {
  const candidates = [
    path.resolve(process.cwd(), ".."),
    path.resolve(__dirname, "..", ".."),
    process.cwd(),
  ];
  const repoRoot = candidates.find((candidate) => fs.existsSync(path.join(candidate, ".git")));
  assert(repoRoot, "Could not locate repository root for deployment validation.");
  return repoRoot;
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}
