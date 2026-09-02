const fs = require("node:fs");
const path = require("node:path");

const repoRoot = findRepoRoot();
const backendRoot = path.join(repoRoot, "backend");

const dockerfile = readText(path.join(backendRoot, "Dockerfile"));
const dockerignore = readText(path.join(backendRoot, ".dockerignore"));
const packageJson = JSON.parse(readText(path.join(backendRoot, "package.json")));
const productionEnvGenerator = readText(path.join(backendRoot, "scripts", "generate-production-env.cjs"));
const renderDeployScript = readText(path.join(backendRoot, "scripts", "deploy-render.cjs"));
const renderYaml = readText(path.join(repoRoot, "render.yaml"));
const endpointWorkflow = readText(path.join(repoRoot, ".github", "workflows", "lenspilot-production-endpoint-check.yml"));
const renderDeployWorkflow = readText(path.join(repoRoot, ".github", "workflows", "lenspilot-render-deploy.yml"));
const testsWorkflow = readText(path.join(repoRoot, ".github", "workflows", "lenspilot-tests.yml"));

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
  "plan: free",
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

assertIncludes(renderDeployWorkflow, "LensPilot Render Deploy", "Render deploy workflow should be named.");
assertIncludes(renderDeployWorkflow, "workflow_dispatch", "Render deploy workflow should be manually runnable.");
assertIncludes(renderDeployWorkflow, "RENDER_DEPLOY_HOOK_URL", "Render deploy workflow should require a deploy hook secret.");
assertIncludes(renderDeployWorkflow, "LENSPILOT_CREATIVE_API_URL", "Render deploy workflow should require the deployed API URL for verification.");
assertIncludes(renderDeployWorkflow, 'method: "POST"', "Render deploy workflow should trigger the deploy hook with POST.");
assertIncludes(renderDeployWorkflow, "npm run check:production-endpoint", "Render deploy workflow should verify the deployed endpoint.");
assertIncludes(renderDeployWorkflow, "Production endpoint check attempt", "Render deploy workflow should wait and retry readiness checks.");
assertIncludes(renderDeployWorkflow, "LENSPILOT_METRICS_TOKEN", "Render deploy workflow should support protected metrics verification.");
assertIncludes(renderDeployWorkflow, "concurrency:", "Render deploy workflow should avoid overlapping deploy attempts.");

assertIncludes(testsWorkflow, "Creative API container smoke", "Main test workflow should smoke test the deploy container.");
assertIncludes(testsWorkflow, "docker build -t lenspilot-creative-api-ci ./backend", "Container smoke test should build the backend Docker image.");
assertIncludes(testsWorkflow, "--publish 127.0.0.1:8787:8787", "Container smoke test should expose the backend only on localhost.");
assertIncludes(testsWorkflow, "LENSPILOT_REQUIRE_PRODUCTION_SAFETY=true", "Container smoke test should run with production safety enabled.");
assertIncludes(testsWorkflow, "LENSPILOT_REQUIRE_SIGNED_PHONE_REQUESTS=true", "Container smoke test should require signed phone requests.");
assertIncludes(testsWorkflow, "LENSPILOT_CLIENT_SIGNING_SECRET", "Container smoke test should configure phone request signing.");
assertIncludes(testsWorkflow, "LENSPILOT_METRICS_TOKEN", "Container smoke test should verify protected metrics.");
assertIncludes(testsWorkflow, 'fetchJSON("/ready")', "Container smoke test should verify the ready endpoint.");

assertIncludes(productionEnvGenerator, "OPENAI_API_KEY=", "Production env generator should keep OpenAI key entry blank.");
assertIncludes(productionEnvGenerator, "RENDER_DEPLOY_HOOK_URL=", "Production env generator should include the Render deploy hook key.");
assertIncludes(productionEnvGenerator, "LENSPILOT_CREATIVE_API_URL=", "Production env generator should include the deployed API URL key.");
assertIncludes(productionEnvGenerator, "LENSPILOT_CREATIVE_API_SIGNING_SECRET", "Production env generator should include the iOS signing-secret key.");
assertIncludes(productionEnvGenerator, "generatedSecretNames", "Production env generator should report secret names without values.");
assertIncludes(productionEnvGenerator, "openAIAPIKeyIncluded: false", "Production env generator should report that it does not include the OpenAI key.");
assertIncludes(renderDeployScript, "RENDER_DEPLOY_HOOK_URL", "Render deploy script should require a deploy hook URL.");
assertIncludes(renderDeployScript, "LENSPILOT_CREATIVE_API_URL", "Render deploy script should require a Creative API URL.");
assertIncludes(renderDeployScript, "runLensPilotProductionEndpointCheck", "Render deploy script should reuse the safe production endpoint checker.");
assertIncludes(renderDeployScript, "render_deploy_hook_failed", "Render deploy script should classify deploy hook failures without printing secrets.");
assertIncludes(renderDeployScript, "deployId: extractDeployId", "Render deploy script should report only the safe deploy id from the hook response.");
assertIncludes(packageJson.scripts["deploy:render"], "deploy-render.cjs", "package.json should expose local Render deployment.");
assertIncludes(packageJson.scripts["production-env:generate"], "generate-production-env.cjs", "package.json should expose production-env generation.");
assertIncludes(packageJson.scripts["test:render-deploy"], "validate-render-deploy.cjs", "package.json should test local Render deployment.");
assertIncludes(packageJson.scripts["test:production-env-generator"], "validate-production-env-generator.cjs", "package.json should test production-env generation.");
assert(packageJson.scripts.test.includes("test:render-deploy"), "Backend test suite should include local Render deploy validation.");
assert(packageJson.scripts.test.includes("test:production-env-generator"), "Backend test suite should include production-env generator validation.");

console.log(JSON.stringify({
  deploymentConfig: true,
  dockerfile: true,
  renderBlueprint: true,
  productionEndpointWorkflow: true,
  renderDeployWorkflow: true,
  renderDeployScript: true,
  containerSmokeWorkflow: true,
  productionEnvGenerator: true,
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
