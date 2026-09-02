# aicamera

LensPilot AI camera prototype with a single-phone iOS capture loop, shared AI contracts, and a mobile-safe creative guidance API.

## Creative API

- Server handler: `backend/api/creative-interpretation.mjs`
- Deployable Node runtime: `backend/server.mjs`
- Container deployment: `backend/Dockerfile`
- Render blueprint: `render.yaml`
- Route contract: `POST /v1/creative-interpretation`
- Health checks: `GET /health` and `GET /ready`
- Server-only secret: `OPENAI_API_KEY`
- Phone-facing config: `LENSPILOT_CREATIVE_API_URL`, optional `LENSPILOT_CREATIVE_API_TOKEN`, and optional request-signing secret supplied through environment or app bundle build settings
- Production readiness metadata: `LENSPILOT_*_ROTATED_AT` dates and `LENSPILOT_SECRET_ROTATION_MAX_AGE_DAYS`
- Local placeholders: see `.env.example`

The iOS app keeps working without the API URL. Direct OpenAI calls from the app require the explicit local-development flag `LENSPILOT_ALLOW_DIRECT_OPENAI_PROVIDER=true`.

Run the backend locally with:

```bash
cd backend
npm start
```

Validate the full deployable server wrapper with:

```bash
cd backend
npm test
```

The backend test also validates `.env.example` so production-safety settings, signed-request settings, metrics settings, secret-rotation metadata, and iOS API settings stay documented without sample secrets.

Generate a local, gitignored production-values file with:

```bash
cd backend
npm run production-env:generate
```

This writes `backend/.env.production.generated` with phone, signing, metrics, and rotation values, while leaving `OPENAI_API_KEY`, `RENDER_DEPLOY_HOOK_URL`, and `LENSPILOT_CREATIVE_API_URL` blank for the real host/account values.

Generate the local iOS build config after the backend is deployed:

```bash
cd backend
npm run ios-config:generate -- --creative-api-url https://lenspilot-creative-api.onrender.com
```

This writes `ios/App/LensPilotApp/Config/LensPilotSecrets.generated.xcconfig`, which is ignored by git and loaded by the tracked `LensPilotConfig.xcconfig`. The generated file contains only the phone-facing Creative API route, phone bearer token, and request-signing secret; it does not include `OPENAI_API_KEY`, the Render deploy hook, or the metrics token. The Xcode project still builds in CI without that local file because the include is optional.

After deployment, verify the live backend posture with:

```bash
cd backend
npm run check:production-endpoint
```

The endpoint check reads `LENSPILOT_CREATIVE_API_URL`, probes `/health` and `/ready`, verifies production safety including fresh secret-rotation metadata, optionally probes `/metrics` when `LENSPILOT_METRICS_TOKEN` is available, and returns only safe pass/fail metadata.

GitHub also includes a manual and scheduled `LensPilot Production Endpoint Check` workflow. Add the deployed route as the repository secret `LENSPILOT_CREATIVE_API_URL`; add `LENSPILOT_METRICS_TOKEN` too if you want the workflow to probe `/metrics`.

The main `LensPilot Tests` workflow also builds `backend/Dockerfile`, starts the Creative API container with production safety enabled, verifies `/health` and `/ready`, and confirms `/metrics` requires authorization.

GitHub also includes a manual `LensPilot Render Deploy` workflow. Add `RENDER_DEPLOY_HOOK_URL` and `LENSPILOT_CREATIVE_API_URL` as repository secrets, then run the workflow to trigger Render and wait until the deployed backend passes the safe endpoint check.

For a local deploy trigger, export the same values into your shell and run:

```bash
cd backend
npm run deploy:render
```

The local deploy command posts to the Render deploy hook, waits for the deployed API URL to report ready, and keeps the hook URL, phone token, metrics token, and OpenAI key out of command output.
