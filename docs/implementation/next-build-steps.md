# Next Build Steps

## Immediate iOS Work

1. Open `ios/Package` from Xcode on macOS and run the `LensPilotCoreTests` test target.
2. Use the in-app calibration queue to collect 24 guided real captures across portrait, landscape, sky, clutter, backlight, horizon, motion, and night scenarios; AI Diagnostics now reports calibration readiness until this coverage is complete.
3. Use the in-app share control to export each selected `iphone_capture_candidate` JSON, then add blind preference labels from the in-app tag control.
4. Check collection gaps with `npm run calibration:readiness`, then import reviewed app exports with `npm run calibration:import-reviewed -- --sample <reviewed-sample.json> --write`.
5. Calibrate the on-device metric weights and guidance priorities against those reviewed samples; the app now loads the bundled manifest into `LensPilotAiCore`.
6. For API-backed creative guidance, create the production Creative API service from `render.yaml`, enter the `sync: false` secret values and fresh `LENSPILOT_*_ROTATED_AT` metadata, then configure the phone build with `LENSPILOT_CREATIVE_API_URL` and, if used, a non-OpenAI `LENSPILOT_CREATIVE_API_TOKEN`. Keep `LENSPILOT_ALLOW_DIRECT_OPENAI_PROVIDER=false` outside local development.

## Completed Single-Phone Runtime Work

- `LensPilotApp.xcodeproj` now builds the same-phone SwiftUI app target against the local Swift package.
- The app target includes camera and photo-library permission strings in `Support/Info.plist`.
- GitHub Actions now builds the iOS app target on macOS in addition to Swift package tests.
- `AVCaptureVideoDataOutput` now feeds `FrameAnalyzer` through the camera screen frame-analysis coordinator.
- Live camera frames are wrapped before async analysis so the app target avoids carrying raw capture buffers across Swift concurrency boundaries.
- `SceneDebugState` now maps into native `SceneState`, so the on-device AI guidance can refresh from live frames instead of only using placeholder state.
- `FrameAnalyzer` now produces on-device horizon roll, face quality, pose, segmentation availability, and motion stability metrics for the AI core.
- Reference photos now use a real `PhotosPicker` flow; the selected image appears as the camera popup and opens in the full same-phone reference viewer.
- Capture now follows the plan's burst count, ranks the captured frames with the on-device best-shot ranker, and shows a same-phone result review.
- Result review now includes an after-capture coaching summary with strong signals and the next best correction for the following shot.
- The live scene bridge is covered by `LensPilotVisionTests`.
- The AI guidance benchmark suite now covers cluttered portrait, tilted horizon, sunset highlight protection, motion blur, backlit face guidance, and ready-to-capture.
- Target Match calibration weights are explicit in Swift and TypeScript, with a CI-validated calibration manifest and protocol.
- The single-phone camera UI can share anonymous calibration candidate JSON for real-capture scoring.
- The single-phone camera UI now has a guided 24-shot calibration queue with local-only progress counts and scenario-specific prompts.
- Calibration exports now tag the active queue scenario in anonymous metadata, and validation checks manifest scenario coverage alignment.
- Reviewed candidate promotion is now scripted and validated before samples can gate Target Match calibration.
- The single-phone app can label the latest captured sample in a score-free blind review sheet and export reviewed calibration JSON.
- Reviewed app exports can now be normalized and appended to the calibration manifest with a validated import command.
- Reviewed-sample imports now print the updated calibration readiness, including remaining capture count, missing domains, and missing scenarios.
- `npm run calibration:readiness` now prints a collector-friendly readiness checklist with per-domain counts, per-scenario counts, and the next missing capture prompt.
- The app target bundles `target-match-calibration.json`, validates its single-phone invariants, and applies its Target Match weights to the live on-device AI core with a safe fallback to defaults.
- Reviewed `iphone_capture` labels now produce small domain-aware guidance boosts, so blind preferences can influence the next selected action without bypassing safety or confidence gates.
- `scripts/test-all.ps1` now fails on external command failures instead of continuing after a broken `npm` or Swift run.
- The live director now stabilizes one-action-at-a-time guidance with TTL, opposite-action suppression, and short completed-action memory to reduce frame-to-frame instruction flipping.
- Personal Visual AI now has consent-gated local learning contracts for customer usage, requirements, accepted/rejected guidance, selected results, ratings, and online-reference usage.
- Optional online inspiration now has a privacy-safe request policy that uses prompt/ShotSpec summaries only and blocks raw live camera frames, private photos, identity data, and precise location without consent.
- The camera screen now exposes Personal Visual AI settings for local learning, optional online inspiration, visible online-reference plans, and deleting the learned on-phone profile.
- The app can fetch public Wikimedia Commons image references from the consent-gated plan and load a selected public image into the same-phone reference popup.
- Online inspiration results are ranked for photographic relevance and warmed through a bounded same-phone thumbnail cache.
- Online inspiration now queries diversified public sources through Wikimedia Commons and Openverse-style public image search, deduplicates repeated assets, and promotes cross-provider variety near the top of the result list.
- Voice intent is wired into the single-phone camera screen with native microphone and speech permissions, on-device speech recognition when available, and typed intent as the fallback path.
- AI Shot Preview V1 now produces a deterministic same-phone `TargetPreview` contract and renders target framing, horizon, achievability, lens, tone, and depth cues over the live camera without generative or cloud claims.
- Same-phone preview adjustments now let the user refine the target with brighter, more sky, less background blur, natural color, and more drama commands from the camera screen; the updated ShotSpec/ShotPlan remains capture-realistic by default.
- Personal Visual AI now persists the learned aggregate profile locally through a sanitized profile store that strips cloud-sync state, caps stored JSON size, drops unknown keys, and never stores raw photos, live frames, or identity data.
- Capture review now lets the user mark a result as Keep or Needs Work, including specific correction reasons that feed same-phone feedback into the local learned profile.
- Learned Personal Visual AI profile data now prefers Keychain encrypted, this-device-only storage on iOS and migrates older UserDefaults profile bytes into the secure store.
- Personal Visual AI settings now show a local learning insight with the current personalization state, top learned aggregate signals, and small guidance boosts.
- Personal Visual AI now produces a consent-gated Creative Plan for event-triggered style interpretation using prompt, ShotSpec, aggregate learned preferences, and public-reference summaries only.
- The in-app AI Diagnostics sheet now checks shot planning, reference popup, online plan, provider health, calibration readiness, local learning, encrypted learning storage, and capture coaching from the same phone.
- AI Diagnostics now verifies the Creative Plan privacy boundary and shows the same concrete shot-brief suggestions that appear in Personal Visual AI settings.
- Creative Plan provider requests now require a payload audit, clamp response length, preserve required safety/reference suggestions, and reject unsafe summaries before any future online reasoning adapter can run.
- Creative interpretation now has a health-gated adapter path that only returns a same-phone creative brief after safe public-source health and audited provider payload checks both pass.
- Creative interpretation now has an optional OpenAI Responses API provider behind that health gate; it sends only audited prompt/ShotSpec/profile/public-reference summaries, requests strict JSON output, disables response storage with `store: false`, and blocks unsafe provider output before showing guidance.
- The repo now includes a mobile-safe Creative API handler at `backend/api/creative-interpretation.mjs`; it owns the server-side OpenAI key, rejects client-supplied OpenAI keys, validates the phone's request envelope, and returns only a safe creative-provider result.
- The repo now includes a deployable plain-Node Creative API runtime at `backend/server.mjs` with `/health`, `/ready`, request body caps, optional CORS allow-listing, optional phone bearer authorization, and local in-memory rate limiting.
- The backend now has a container deployment path through `backend/Dockerfile`, a Render blueprint in `render.yaml`, and a manual/daily GitHub workflow for safe production endpoint checks.
- GitHub Actions now builds the Creative API Docker image and smoke-tests the deploy container with production safety, signed request configuration, fresh rotation metadata, and protected metrics.
- The repo now includes a manual GitHub `LensPilot Render Deploy` workflow that triggers a Render deploy hook and waits for the live Creative API endpoint check to pass.
- The backend now includes `npm run deploy:render`, a local deploy trigger that posts to the Render deploy hook and waits for the live Creative API endpoint check to pass without printing secrets.
- `npm run production-env:generate` now creates a gitignored local production-values file with generated phone, signing, metrics, and rotation metadata values while leaving account-specific host values blank.
- Creative API deployments can now opt into production-safety enforcement with `LENSPILOT_REQUIRE_PRODUCTION_SAFETY=true`; `/ready` and `npm run preflight:production` fail closed until server OpenAI configuration, phone bearer authorization, signed phone requests, metrics authorization, fresh secret-rotation metadata, CORS policy, request caps, rate limits, and the single-phone privacy boundary are safe.
- The iOS Creative API provider can sign same-phone backend requests with `LENSPILOT_CREATIVE_API_SIGNING_SECRET`, and the backend can require matching timestamped HMAC signatures with replay protection through `LENSPILOT_CLIENT_SIGNING_SECRET` and `LENSPILOT_REQUIRE_SIGNED_PHONE_REQUESTS=true`.
- The Creative API now exposes safe aggregate operational telemetry at `GET /metrics`, with bounded recent events and explicit no-retention flags for request bodies, prompt text, client IPs, auth headers, photos, identity data, precise location, and raw learning events.
- `.env.example` now includes the full backend and iOS Creative API configuration surface, and backend tests fail if production-safety, signed-request, metrics, secret-rotation metadata, or phone-facing API keys drift out of the template.
- `npm run check:production-endpoint` now verifies deployed `/health`, `/ready`, and optional `/metrics` posture without sending prompts or calling OpenAI, and fails closed if production safety, signed requests, fresh secret-rotation metadata, CORS, limits, or single-phone privacy regress.
- The iOS app now prefers `LENSPILOT_CREATIVE_API_URL` through `LensPilotCreativeInterpretationAPIProvider` from environment or app bundle build settings; direct OpenAI calls require the explicit local-development flag `LENSPILOT_ALLOW_DIRECT_OPENAI_PROVIDER=true`.
- Target Match calibration readiness now reports reviewed real-capture counts, missing domains, and missing scenarios so production calibration cannot be mistaken for seed-fixture coverage.
- AI Diagnostics now includes an in-app calibration readiness checklist with missing domains, missing scenarios, and a one-tap action that selects the next capture scenario on the same phone.

## Single-Phone Verification Checklist

- The camera preview, reference popup, full reference viewer, guidance, capture, and result review all run on one device.
- Front camera self-shot mode never assumes a second person or device.
- Reference photo viewing does not stop the live camera session.
- Personal learning events are structured signals only; they do not store raw photos, upload live camera frames, or enable identity recognition.
- Online inspiration is optional and consent-gated; the base camera loop remains usable without network access.
- Delete Learned Profile resets the local profile on the same phone without affecting the reference popup, camera preview, or capture flow.
- Online source lookup is user-triggered from settings and uses prompt-derived search queries only; live camera frames and private reference photos are not uploaded.
- Cloud is not required for camera preview, basic ShotSpec, basic ShotPlan, guidance, capture, or best-shot selection.
- Voice input is tap-triggered on the same phone and uses the same ShotSpec path as typed intent.
- AI Shot Preview V1 is capture-realistic by default, uses the ShotPlan composition target, and explicitly marks previews that would require AI enhancement after capture.
- Preview adjustment controls run locally, preserve the single-phone privacy invariant, and do not upload raw camera frames or private reference photos.
- Learned profile persistence stores only sanitized aggregate preference signals on the same phone and strips cloud personalization sync.
- Learning insight displays aggregate usage, requirement, action, and public-reference signals only; it does not expose raw photos, live frames, identity data, or cloud personalization state.
- Creative interpretation is event-triggered and consent-gated; it uses safe summaries only and blocks raw camera frames, private photos, identity data, precise location, raw learning events, and generative-output claims.
- Creative interpretation request payloads are audited before provider use; summaries containing raw-frame, image-byte, EXIF/GPS, precise-location, private-photo, identity, or raw-learning-event terms are rejected.
- Creative interpretation provider execution is health-gated; missing, unsafe, failed, or empty public-source health blocks the provider path before any brief is produced.
- OpenAI creative guidance is API-backed through the LensPilot backend runtime; the same-phone camera loop still works without the API URL, and provider secrets are never accepted from or returned to the phone.
- Creative API provider failures are safely classified for same-phone diagnostics, including exhausted-credit and retryability signals, without exposing provider secrets or raw provider payloads.
- Same-phone Creative Plan and AI Diagnostics surfaces show clear, sanitized provider failure messages, including exhausted-credit blocks, while preserving the offline camera loop.
- Production Creative API readiness can be made fail-closed before deployment by setting `LENSPILOT_REQUIRE_PRODUCTION_SAFETY=true`; readiness metadata remains safe and does not expose OpenAI keys or phone bearer tokens.
- Production readiness requires fresh `LENSPILOT_*_ROTATED_AT` metadata for configured secrets and keeps the accepted rotation window at or below 90 days.
- Deployment config marks production secrets as `sync: false`; the GitHub production endpoint workflow requires only the deployed Creative API URL plus an optional metrics token, and the Render deploy workflow/local deploy command require only a deploy hook URL plus the deployed Creative API URL.
- Signed Creative API request auth rejects missing, stale, invalid, and replayed same-phone calls before provider use; replay storage keeps bounded hashes only, not raw request bodies, prompts, photos, or request ids.
- Creative API metrics can be disabled or protected with `LENSPILOT_METRICS_TOKEN`; production readiness requires metrics authorization whenever metrics are enabled.
- Production endpoint checks use safe GET probes only and do not submit creative prompts, private references, live frames, learning events, or OpenAI credentials.
- On iOS, learned profile persistence prefers Keychain encrypted, this-device-only storage and removes legacy UserDefaults bytes after migration or save.
- Capture feedback records structured ratings, guidance outcomes, and selected correction reasons only; it does not store the captured photo as a learning event.
- After-capture coaching uses score summaries and ranked-shot metadata only; it does not store or upload raw photos.
- Calibration queue progress stores selected scenario IDs and counts only; photos remain outside the queue state and exports stay user-triggered.
- Calibration export metadata may include the selected queue scenario id, but it still excludes raw photos, live frames, identity labels, and online-source data.
- Calibration readiness only passes after same-phone real captures meet the required review count, domain coverage, and scenario coverage.
- The diagnostics checklist can select the next missing calibration scenario without leaving the single-phone app flow.

## MVP Boundary

Do not build video director, social features, cloud storage, generative editing, or multi-device capture until the single-phone photo loop produces measurably better images.
