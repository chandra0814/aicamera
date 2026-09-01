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
- `LENSPILOT_REQUIRE_PRODUCTION_SAFETY`: set `true` in deployed environments so `/ready` fails unless server OpenAI configuration, phone bearer authorization, signed phone requests, metrics authorization, CORS policy, request caps, rate limits, and the single-phone privacy boundary are all production-safe.

## Production Preflight

```bash
cd backend
npm run preflight:production
```

The preflight prints only safe configuration metadata and exits non-zero when production safety checks fail. It never prints the OpenAI key, phone bearer token, metrics bearer token, or signing secret.

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

## Provider Errors

OpenAI failures stay behind the LensPilot backend boundary. The API returns safe metadata such as `openai_credit_balance_exhausted`, provider HTTP status, sanitized provider error type/code, `retryable`, and `blockedByBilling`; it never forwards provider secrets, raw provider payloads, or client-supplied OpenAI keys back to the phone.
