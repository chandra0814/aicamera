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
- `POST /v1/creative-interpretation`

## Environment

- `OPENAI_API_KEY`: server-only OpenAI key.
- `LENSPILOT_CREATIVE_API_TOKEN`: optional bearer token expected from the phone. This is not an OpenAI key.
- `LENSPILOT_OPENAI_MODEL`: optional model override, default `gpt-5.6-luna`.
- `LENSPILOT_OPENAI_WEB_SEARCH`: set `false` to disable OpenAI web search.
- `LENSPILOT_API_HOST`: local bind host, default `127.0.0.1`.
- `PORT` or `LENSPILOT_API_PORT`: local bind port, default `8787`.
- `LENSPILOT_ALLOWED_ORIGINS`: optional comma-separated browser origins for CORS.
- `LENSPILOT_MAX_REQUEST_BYTES`: request body cap, default `65536`.
- `LENSPILOT_RATE_LIMIT_WINDOW_MS`: local in-memory rate-limit window, default `60000`.
- `LENSPILOT_RATE_LIMIT_MAX`: local in-memory request count per client per window, default `30`.

## Validation

```bash
cd backend
npm test
```

The validation starts the server on a random local port, checks health/readiness/CORS, verifies client authorization, exercises the creative route with a fake OpenAI transport, and confirms rate limiting. It does not require a real OpenAI key.

## Provider Errors

OpenAI failures stay behind the LensPilot backend boundary. The API returns safe metadata such as `openai_credit_balance_exhausted`, provider HTTP status, sanitized provider error type/code, `retryable`, and `blockedByBilling`; it never forwards provider secrets, raw provider payloads, or client-supplied OpenAI keys back to the phone.
