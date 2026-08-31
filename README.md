# aicamera

LensPilot AI camera prototype with a single-phone iOS capture loop, shared AI contracts, and a mobile-safe creative guidance API.

## Creative API

- Server handler: `backend/api/creative-interpretation.mjs`
- Deployable Node runtime: `backend/server.mjs`
- Route contract: `POST /v1/creative-interpretation`
- Health checks: `GET /health` and `GET /ready`
- Server-only secret: `OPENAI_API_KEY`
- Phone-facing config: `LENSPILOT_CREATIVE_API_URL` and optional `LENSPILOT_CREATIVE_API_TOKEN`, supplied through environment or app bundle build settings
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
