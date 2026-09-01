# LensPilot AI Core Status

This implementation completes the MVP AI control skeleton, not the final production intelligence. The current AI is deterministic and testable so the camera can work reliably before expensive models are introduced.

## Implemented Now

- Intent Engine: maps natural-language prompts into `ShotSpec`.
- Shot Planner: maps `ShotSpec + SceneState + DeviceCapability` into `ShotPlan`.
- Guidance Policy: selects one best next action using confidence, expected gain, priority, interaction cost, safety qualifier, and small reviewed-sample calibration boosts.
- Guidance Stabilizer: holds one action long enough to be usable, suppresses immediate opposite movement/rotation instructions, and remembers just-completed movement when the scene reaches ready state.
- Target Match Engine: calculates normalized sub-scores and an overall match from measured scene values.
- Preview Safety Engine: enforces Natural, Enhanced, and Creative labels.
- Target Preview Engine: converts the safe ShotPlan into a deterministic same-phone preview contract with achievable framing, lens, tone, depth, Target Match, and privacy flags.
- Preview adjustment intent: same-phone commands such as brighter, show more sky, less background blur, natural colors, and more drama now update ShotSpec and ShotPlan fields without changing privacy or cloud posture.
- Best-Shot Ranker: ranks burst candidates by sharpness, exposure, face quality, pose, composition, background, and intent match.
- Personal Visual Learning Engine: converts consented customer usage, requirements, accepted/rejected guidance, selected corrections, selected results, ratings, and online-reference usage into a local preference profile with small guidance boosts.
- Capture feedback learning: the same-phone result review can record good/bad customer feedback and specific correction reasons as structured local Personal Visual AI signals.
- Personal Visual Learning Insight: summarizes aggregate learned style, framing, requirements, guidance actions, and public-inspiration usage so the user can see what the AI is adapting from.
- Online Reference Policy: can produce a consent-gated public-inspiration request plan from prompt and ShotSpec only, while explicitly blocking raw live camera frames, private photos, identity data, and precise location without consent.
- Creative Interpretation Plan: produces an event-triggered shot brief from prompt, ShotSpec, aggregate learned preferences, and public-reference summaries only; diagnostics block it if raw frames, private photos, identity data, precise location, raw learning events, or generative-output claims are included.
- Creative Interpretation Request Audit: builds a bounded provider request only after a payload audit confirms safe summaries, required blocklists, privacy flags, and suggestion content.
- Health-Gated Creative Interpretation Adapter: runs a creative brief only when the audited request and public-source health snapshot are both safe, available, and free of raw camera frames, private photos, identity data, precise location, and raw learning events.
- Mobile-Safe Creative API: `backend/api/creative-interpretation.mjs` exposes a server-side `/v1/creative-interpretation` handler that keeps `OPENAI_API_KEY` on the backend, rejects client-supplied OpenAI keys, reruns request and health-gate safety checks, sends audited text only to OpenAI's Responses API, uses `store: false`, requests strict JSON schema output, and blocks unsafe provider output.
- Deployable Creative API Runtime: `backend/server.mjs` exposes `/health`, `/ready`, and `/v1/creative-interpretation` on plain Node with request body caps, optional CORS allow-listing, optional phone bearer authorization, and local in-memory rate limiting.
- Creative API Production Preflight: `/ready` can now enforce `LENSPILOT_REQUIRE_PRODUCTION_SAFETY=true`, and `npm run preflight:production` validates server OpenAI configuration, phone bearer authorization, signed phone requests, metrics authorization, CORS policy, request caps, rate limits, and the single-phone privacy boundary without exposing secrets.
- Creative API Config Template Guard: backend tests now validate `.env.example` for every server/iOS Creative API key, blank secret placeholders, production-safe default caps, signed-request settings, metrics settings, and the full iOS API route path.
- Creative API Production Endpoint Check: `npm run check:production-endpoint` verifies a deployed backend's `/health`, `/ready`, and optional `/metrics` posture without sending prompts or calling OpenAI, and fails if production safety, signed requests, metrics protection, CORS, limits, or single-phone privacy regress.
- Signed Phone Request Auth: the iOS Creative API provider can now add timestamped HMAC request signatures, and the backend can require them with replay protection so copied or stale phone requests are rejected before provider use.
- Safe Operational Telemetry: `GET /metrics` now reports aggregate Creative API status counts, error-code counts, provider status counts, and bounded recent events without storing or returning request bodies, prompts, client IPs, authorization headers, raw photos, identity data, precise location, or raw learning events.
- Creative API provider failures now return sanitized diagnostic metadata, including exhausted-credit classification, provider HTTP status, retryability, and billing-blocked flags, without exposing secrets or raw provider payloads to the phone.
- The same-phone camera UI now maps sanitized OpenAI and Creative API provider errors into clear diagnostics such as `OpenAI credits exhausted`, while defensively redacting secret-looking tokens from provider messages.
- Optional iOS Creative API Provider: when `LENSPILOT_CREATIVE_API_URL` is available from environment or app bundle build settings, the app sends the audited creative request and health gate to the LensPilot backend. Direct OpenAI provider use is now limited to explicit development opt-in with `LENSPILOT_ALLOW_DIRECT_OPENAI_PROVIDER=true`.
- Single-phone invariant: `ShotSpec.constraints.singlePhoneOnly` is required and true.
- Native Swift AI core: iOS now has on-device `SceneState`, `LensPilotAiCore`, `TargetMatchEngine`, `GuidancePolicy`, `PreviewSafetyEngine`, and `BestShotRanker` equivalents.
- App wiring: the iOS camera screen view model calls the native AI core and displays AI guidance plus Target Match from scene inputs.
- AI Shot Preview V1: the iOS camera overlay now renders the deterministic target frame, optional horizon guide, estimated achievability, preview label, lens, tone, and depth on the live same-phone camera.
- The camera screen includes a compact adjustment menu that reruns the local AI preview loop for brighter, more sky, less background blur, natural color, and more drama requests.
- Live scene bridge: `FrameAnalyzer` output now maps `SceneDebugState` into native `SceneState`, and the camera screen refreshes AI guidance from analyzed live frames.
- Live quality metrics: `FrameAnalyzer` now derives horizon roll, face quality, pose, segmentation availability, and motion stability signals on-device.
- Reference-photo loop: selected library images stay on-device, appear in the camera popup, and open in the same-phone full reference viewer.
- Capture review loop: the app captures a plan-sized burst, ranks frame candidates on-device, and presents the best result plus alternatives.
- After-capture coaching: the result review now summarizes strong score signals, the weakest improvement area, and a concrete next-shot correction without storing or uploading raw photos.
- AI guidance benchmark suite: six deterministic calibration cases now cover cluttered portrait, tilted horizon, sunset highlight protection, motion blur, backlit face guidance, and ready-to-capture.
- Target Match calibration scaffold: scoring weights are explicit in Swift and TypeScript, and CI validates the calibration manifest.
- Calibration sample export: the single-phone camera UI can share anonymous `iphone_capture_candidate` JSON with prompt, scene, device, guidance, and Target Match data.
- Guided calibration queue: the app now tracks 24 target real captures across portrait, landscape, sky, clutter, backlight, horizon, motion, and night scenarios.
- Calibration exports preserve the active queue scenario as `captureMetadata.calibrationScenarioId`, and validation reports reviewed real-capture coverage by scenario.
- Calibration promotion tool: reviewed candidates can be promoted into `iphone_capture` manifest entries only when single-phone privacy flags, domain labels, blind preference labels, and expected Target Match ranges are present.
- In-app blind review labeling: after capture, the same phone opens a score-free label sheet for domain, preferred fix, ranked weaknesses, reviewer count, and reviewed-sample export.
- Reviewed-sample importer: app exports can be normalized and appended to the calibration manifest only after single-phone privacy, blind-review, domain, and expected score-range validation passes.
- Runtime calibration loading: the iOS app bundles the Target Match calibration manifest, validates that it remains single-phone only, and initializes the on-device AI core with reviewed scoring weights and domain-aware guidance-priority boosts when available.
- Live director stabilization: the iOS camera screen now applies guidance TTL, opposite-action suppression, and completed-action memory before updating the single on-screen instruction.
- Personal Visual AI contracts now support local-only learning from structured user behavior and optional online inspiration plans without making cloud or online access required for the camera loop.
- Personal Visual Profile Store now persists the learned aggregate profile locally with size caps, schema sanitization, cloud-sync stripping, and no raw photo, live-frame, or identity storage.
- Capture result review now exposes explicit Keep and Needs Work feedback controls, including a reason menu for lighting, background, horizon, pose, sharpness, exposure, reference match, sky, and framing corrections.
- Personal Visual AI app controls now let the user enable local learning, enable optional online inspiration, see the current online-reference plan, and delete the local learned profile from the same phone.
- Online inspiration can now fetch public image references from Wikimedia Commons from prompt-derived queries only, display them in the same-phone settings sheet, and load a selected public result into the existing reference popup.
- Online inspiration results are now ranked for photographic relevance and warmed into a bounded local thumbnail cache before display.
- Online inspiration now supports multiple public providers, starting with Wikimedia Commons and Openverse-style public image search, with deduplication and source-diverse ranking so one provider does not dominate the first results.
- Calibration queue progress is stored as local counts and the active scenario only; it does not store photos, live frames, identity labels, or cloud state.
- Personal Visual AI learned-profile storage now prefers Keychain encrypted, this-device-only storage on iOS, migrates legacy local profile bytes out of UserDefaults, and reports storage protection in AI Diagnostics.
- Personal Visual AI settings now show the local learning insight, including the current personalization state, top aggregate signals, and small guidance boosts.
- Target Match calibration readiness now reports whether reviewed same-phone captures satisfy the required sample count, domain coverage, scenario coverage, and blind-review minimum before production calibration is considered ready.
- AI Diagnostics now surfaces that calibration readiness signal from the bundled manifest alongside shot planning, reference popup, online source health, local learning, encrypted learning storage, and capture coaching.
- AI Diagnostics now shows the missing calibration domains and scenarios in the app and can select the next missing capture scenario directly in the single-phone camera flow.
- Personal Visual AI settings and AI Diagnostics now show the consent-gated Creative Plan for the current prompt, including safe input summaries and concrete lighting, composition, lens, color, reference, and safety suggestions.
- Creative Plan diagnostics now use the payload audit that a future provider call would use, so unsafe summaries are blocked before any online reasoning adapter can run.

## Not Yet Production AI

- No trained aesthetic model yet.
- No completed real iPhone target-match calibration dataset yet; the bundled seed manifest currently reports `needs_more_samples` until 24 reviewed real captures are imported.
- No Core ML/TFLite production model bundle yet.
- No deployed production Creative API host, Apple App Attest verification, managed edge rate limiting, durable monitoring sink, or key-rotation runbook yet; the backend now includes production-safety preflight, signed request enforcement, replay protection, safe in-memory telemetry, and a deployed-endpoint posture check before deployment.
- No generative preview engine yet.
- No embedding sync or cloud personalization sync yet.
- No live production monitoring, endpoint health checks, or provider-specific quality analytics for public inspiration yet.
- No blind-rater evaluation data yet.

## Why This Order

LensPilot must remain a reliable camera first. A deterministic AI core lets us prove the interaction loop, collect structured data, and measure whether guidance improves photos before adding model complexity.

## Required Next AI Work

1. Collect real portrait, landscape, sky, clutter, backlight, horizon, motion, and night samples from iPhone captures.
2. Use the calibration readiness report and AI Diagnostics to confirm all 24 reviewed captures satisfy the required domains, scenarios, and blind-review minimum.
3. Tune benchmark thresholds, sub-score weights, and guidance-priority boosts against blind preference tests now that the app can load the manifest at runtime.
4. Deploy the Creative API runtime with `LENSPILOT_REQUIRE_PRODUCTION_SAFETY=true` and signed request enforcement, run `npm run check:production-endpoint` against the deployed route, then add Apple App Attest verification, managed edge rate limits, provider-specific quality analytics, and key-rotation operations.
