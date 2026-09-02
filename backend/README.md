# LensPilot Creative API

This backend keeps the OpenAI API key off the phone. The iOS app sends only an audited creative-request envelope to `POST /v1/creative-interpretation`; the server validates that envelope again before calling OpenAI.

## Local Run

```bash
cd backend
npm start
```

Default local URLs:

- `GET /health`
- `GET /ready`
- `GET /metrics`
- `POST /v1/creative-interpretation`

## Environment

- `OPENAI_API_KEY`: server-only OpenAI key.
- `LENSPILOT_CREATIVE_API_TOKEN`: optional bearer token expected from the phone. This is not an OpenAI key.
- `LENSPILOT_CLIENT_SIGNING_SECRET`: optional HMAC secret for signed same-phone Creative API requests. This is not an OpenAI key.
- `LENSPILOT_REQUIRE_SIGNED_PHONE_REQUESTS`: set `true` to require `X-LensPilot-Request-Id`, `X-LensPilot-Timestamp`, and `X-LensPilot-Signature` on Creative API requests.
- `LENSPILOT_SIGNATURE_TOLERANCE_MS`: signed-request clock window, default `300000`.
- `LENSPILOT_SIGNATURE_REPLAY_MAX_ENTRIES`: maximum recent signed request ids retained for replay protection, default `1000`.
- `LENSPILOT_OPENAI_MODEL`: optional model override, default `gpt-5.6-luna`.
- `LENSPILOT_OPENAI_WEB_SEARCH`: set `false` to disable OpenAI web search.
- `LENSPILOT_API_HOST`: local bind host, default `127.0.0.1`.
- `PORT` or `LENSPILOT_API_PORT`: local bind port, default `8787`.
- `LENSPILOT_ALLOWED_ORIGINS`: optional comma-separated browser origins for CORS.
- `LENSPILOT_MAX_REQUEST_BYTES`: request body cap, default `65536`.
- `LENSPILOT_RATE_LIMIT_WINDOW_MS`: local in-memory rate-limit window, default `60000`.
- `LENSPILOT_RATE_LIMIT_MAX`: local in-memory request count per client per window, default `30`.
- `LENSPILOT_ENABLE_METRICS`: set `false` to disable `GET /metrics`, default `true`.
- `LENSPILOT_METRICS_TOKEN`: optional bearer token for `GET /metrics`; required when production safety is enforced and metrics are enabled.
- `LENSPILOT_MAX_METRIC_EVENTS`: maximum safe recent events retained in memory, default `100`, capped at `500`.
- `LENSPILOT_SECRET_ROTATION_MAX_AGE_DAYS`: maximum accepted age for production secret rotation metadata, default `90`.
- `LENSPILOT_OPENAI_KEY_ROTATED_AT`: ISO date or timestamp for the last server OpenAI key rotation.
- `LENSPILOT_CREATIVE_API_TOKEN_ROTATED_AT`: ISO date or timestamp for the last phone bearer token rotation.
- `LENSPILOT_CLIENT_SIGNING_SECRET_ROTATED_AT`: ISO date or timestamp for the last phone request-signing secret rotation.
- `LENSPILOT_METRICS_TOKEN_ROTATED_AT`: ISO date or timestamp for the last metrics token rotation.
- `LENSPILOT_REQUIRE_PRODUCTION_SAFETY`: set `true` in deployed environments so `/ready` fails unless server OpenAI configuration, phone bearer authorization, signed phone requests, metrics authorization, secret rotation metadata, CORS policy, request caps, rate limits, and the single-phone privacy boundary are all production-safe.

## Secret Rotation Metadata

Production readiness requires fresh rotation metadata for the server OpenAI key, phone bearer token, phone request-signing secret, and metrics token when metrics are enabled. Set each `LENSPILOT_*_ROTATED_AT` value to an ISO date like `2026-09-01` or an ISO timestamp. `/ready` reports only safe metadata: whether each secret is configured, the last rotation timestamp, age in days, and pass/fail status.

The rotation window must stay at or below `90` days in production. The metadata does not rotate keys by itself; it makes the deployable API fail closed until key rotation has happened and been recorded.

## Production Preflight

```bash
cd backend
npm run preflight:production
```

The preflight prints only safe configuration metadata and exits non-zero when production safety checks fail, including missing, invalid, stale, or over-wide secret rotation metadata. It never prints the OpenAI key, phone bearer token, metrics bearer token, or signing secret.

## Production Values File

```bash
cd backend
npm run production-env:generate
```

This writes `backend/.env.production.generated`, which is ignored by git. The file contains generated phone bearer, request-signing, metrics, and rotation metadata values. It intentionally leaves `OPENAI_API_KEY`, `RENDER_DEPLOY_HOOK_URL`, and `LENSPILOT_CREATIVE_API_URL` blank because those must come from the real OpenAI project, Render service, and deployed API URL.

## Container Deployment

The backend can be deployed from `backend/Dockerfile`. The container runs `node server.mjs` as the unprivileged `node` user, binds to `0.0.0.0`, exposes port `8787`, and includes a `/health` container health check.

`render.yaml` provides the first production blueprint. Before creating the Render service, enter real environment values for:

- `OPENAI_API_KEY`
- `LENSPILOT_ALLOWED_ORIGINS`
- `LENSPILOT_CREATIVE_API_TOKEN`
- `LENSPILOT_CLIENT_SIGNING_SECRET`
- `LENSPILOT_METRICS_TOKEN`
- `LENSPILOT_OPENAI_KEY_ROTATED_AT`
- `LENSPILOT_CREATIVE_API_TOKEN_ROTATED_AT`
- `LENSPILOT_CLIENT_SIGNING_SECRET_ROTATED_AT`
- `LENSPILOT_METRICS_TOKEN_ROTATED_AT`

The blueprint marks those values `sync: false` so they are not committed to the repo. Production safety is enabled in the blueprint, signed phone requests are required, metrics stay protected, and the rotation window remains `90` days.

## Production Endpoint Check

After deployment, set `LENSPILOT_CREATIVE_API_URL` to the phone-facing route and run:

```bash
cd backend
npm run check:production-endpoint
```

The checker performs safe `GET` probes against `/health` and `/ready`, then checks that production safety is enforced, phone authorization is configured, signed requests are required, secret rotation metadata is fresh, request/rate limits are bounded, wildcard CORS is blocked, and the single-phone privacy boundary is still reported. If `LENSPILOT_METRICS_TOKEN` is present, it also probes `/metrics` and verifies the telemetry retention boundary. It never sends a creative prompt or calls OpenAI.

GitHub Actions also includes `LensPilot Production Endpoint Check`. Configure the repository secret `LENSPILOT_CREATIVE_API_URL` with the deployed `/v1/creative-interpretation` route, and optionally configure `LENSPILOT_METRICS_TOKEN` so the workflow can probe `/metrics`. The workflow can be run manually and also runs daily.

## Render Deploy Workflow

GitHub Actions includes `LensPilot Render Deploy`. Configure the repository secrets `RENDER_DEPLOY_HOOK_URL` and `LENSPILOT_CREATIVE_API_URL`, plus `LENSPILOT_METRICS_TOKEN` when metrics probing is desired. Running the workflow triggers the Render deploy hook and retries `npm run check:production-endpoint` until the deployed backend reports a safe ready state or the deployment wait expires.

## Metrics

`GET /metrics` returns aggregate operational telemetry for the Creative API: response counts, status counts, safe error-code counts, provider status counts, and bounded recent events. It does not store or return request bodies, prompt text, client IPs, authorization headers, raw photos, identity data, precise location, or raw learning events.

For production, set `LENSPILOT_METRICS_TOKEN` or disable metrics with `LENSPILOT_ENABLE_METRICS=false` before enabling `LENSPILOT_REQUIRE_PRODUCTION_SAFETY=true`.

## Signed Phone Requests

When `LENSPILOT_REQUIRE_SIGNED_PHONE_REQUESTS=true`, the phone must sign each Creative API request with:

- `X-LensPilot-Request-Id`: unique per request.
- `X-LensPilot-Timestamp`: milliseconds since epoch.
- `X-LensPilot-Signature`: `v1=` plus base64url HMAC-SHA256.

The signature covers the method, route path, timestamp, request id, and raw request-body SHA-256. The server rejects missing, stale, invalid, or replayed signatures and retains only a bounded hash of used request ids for replay protection.

## Validation

```bash
cd backend
npm test
```

The validation starts the server on a random local port, checks health/readiness/CORS, verifies client authorization, verifies signed request and replay protection, exercises the creative route with a fake OpenAI transport, confirms rate limiting, validates production-safety readiness failures, and checks safe operational telemetry. It does not require a real OpenAI key.

The backend test also validates the root `.env.example` template, production deployment config, production env generator, Render deploy workflow, and the production endpoint checker. It requires every server/iOS Creative API configuration key, keeps placeholder secrets and rotation timestamps blank, verifies the iOS URL points at `/v1/creative-interpretation`, verifies the Docker/Render/GitHub endpoint-check configuration, and checks that example request caps, rate limits, signature windows, replay cache size, endpoint-check timeout, secret rotation window, and telemetry retention remain production-safe.

## Provider Errors

OpenAI failures stay behind the LensPilot backend boundary. The API returns safe metadata such as `openai_credit_balance_exhausted`, provider HTTP status, sanitized provider error type/code, `retryable`, and `blockedByBilling`; it never forwards provider secrets, raw provider payloads, or client-supplied OpenAI keys back to the phone.
