const fs = require("node:fs");
const http = require("node:http");
const { createHash, createHmac, timingSafeEqual } = require("node:crypto");
const { pathToFileURL } = require("node:url");

const apiSource = fs
  .readFileSync("api/creative-interpretation.mjs", "utf8")
  .replace(/^export /gm, "");
const apiModule = Function(`${apiSource}
return {
  createLensPilotCreativeInterpretationApi,
  lensPilotCreativeInterpretationApiDefaults,
  lensPilotCreativeInterpretationApiPrivacy,
};
`)();

const serverSource = fs
  .readFileSync("server.mjs", "utf8")
  .replace(/^import http from "node:http";\r?\n/, "")
  .replace(/^import \{ createHash, createHmac, timingSafeEqual \} from "node:crypto";\r?\n/, "")
  .replace(/^import \{ pathToFileURL \} from "node:url";\r?\n/, "")
  .replace(/import \{\r?\n[\s\S]*?\} from "\.\/api\/creative-interpretation\.mjs";\r?\n/, "")
  .replace(/^export /gm, "")
  .replace(/import\.meta\.url/g, "\"file:///lenspilot/backend/server.mjs\"");

const serverModule = Function(
  "http",
  "createHash",
  "createHmac",
  "timingSafeEqual",
  "pathToFileURL",
  "createLensPilotCreativeInterpretationApi",
  "lensPilotCreativeInterpretationApiDefaults",
  "lensPilotCreativeInterpretationApiPrivacy",
  `${serverSource}
return {
  describeLensPilotCreativeServerConfig,
};
`
)(
  http,
  createHash,
  createHmac,
  timingSafeEqual,
  pathToFileURL,
  apiModule.createLensPilotCreativeInterpretationApi,
  apiModule.lensPilotCreativeInterpretationApiDefaults,
  apiModule.lensPilotCreativeInterpretationApiPrivacy
);

const report = serverModule.describeLensPilotCreativeServerConfig({
  environment: process.env,
  requireProductionSafety: true,
});

const output = {
  service: report.service,
  apiVersion: report.apiVersion,
  status: report.productionSafety.ready ? "ready" : "not_ready",
  paths: report.paths,
  openAIConfigured: report.openAIConfigured,
  clientAuthorizationConfigured: report.clientAuthorizationConfigured,
  clientSignatureConfigured: report.clientSignatureConfigured,
  signedRequestsRequired: report.signedRequestsRequired,
  metricsAuthorizationConfigured: report.metricsAuthorizationConfigured,
  rateLimit: report.rateLimit,
  signedRequestPolicy: report.signedRequestPolicy,
  requestBody: report.requestBody,
  telemetry: report.telemetry,
  cors: report.cors,
  productionSafety: report.productionSafety,
  privacy: report.privacy,
};

console.log(JSON.stringify(output, null, 2));

if (!report.productionSafety.ready) {
  process.exitCode = 1;
}
