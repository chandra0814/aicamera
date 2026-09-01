# Test Status

## Runnable In This Workspace

- JSON parse validation for all `.json` files.
- Backend Creative API server validation with local HTTP health/readiness checks, CORS allow-list checks, phone bearer authorization, fake-provider creative route execution, rate-limit checks, and production-safety readiness failures.
- `npm run validate` inside `shared/typescript`, covering:
  - `singlePhoneOnly` invariant
  - identity recognition disabled
  - telephoto lens recommendation from fixture device capabilities
  - normalized Target Match
  - safety-qualified movement guidance
  - deterministic AI guidance benchmarks with manifest-derived guidance calibration
  - Target Match calibration manifest validation, including candidate-sample privacy checks
  - Target Match calibration readiness reporting for missing real-capture counts, domains, and scenarios
  - collector-friendly calibration readiness checklist validation in human and JSON modes
  - reviewed candidate promotion into labeled `iphone_capture` calibration samples
  - reviewed-sample importer readiness summaries after manifest writes
  - guided calibration queue validation for eight real-capture scenarios, 24 target captures, supported domains, manifest `requiredScenarios` alignment, and sanitized local progress
  - reviewed app export normalization before manifest import
  - guidance stabilizer checks for immediate opposite-action suppression and completed-action memory
  - Personal Visual AI validation for consent-gated learning, local learning insights, creative interpretation plans, creative payload audits, health-gated creative provider execution, positive/negative capture feedback, correction-reason learning boosts, small personalization boosts, and online-reference privacy boundaries
  - Personal Visual AI local profile storage sanitization, preferred encrypted-at-rest policy, legacy-store migration flags, cloud-sync stripping, and oversized-profile rejection
  - Wikimedia Commons online-inspiration request construction and public image response parsing
  - Openverse-style public image request construction and response parsing
  - online-inspiration source-diverse result ranking and thumbnail cache eviction
  - deterministic Target Preview privacy, safety label, achievability, and composition-overlay validation
  - same-phone Target Preview adjustment validation for brighter, more sky, less background blur, and natural-color commands
  - after-capture coaching validation for strong signals, next-shot corrections, and single-phone privacy flags
  - single-phone AI diagnostics validation for shot planning, reference popup, online source health, audited creative interpretation, calibration readiness, local learning, encrypted learning storage, and capture coaching
  - OpenAI Responses API creative-provider payload and parser validation for audited text-only requests, `store: false`, strict JSON schema output, optional public web search, nested `output_text` parsing, and unsafe-provider-output rejection
  - LensPilot Creative API validation for the server-side `/v1/creative-interpretation` route, backend-only OpenAI key use, client OpenAI-key rejection, unsafe request rejection, missing server-key failure, and unsafe-provider-output rejection
- `LensPilotVisionTests` on macOS CI, covering the `SceneDebugState` to native `SceneState` bridge and on-device quality metric mapping.
- `LensPilotCoreTests` on macOS CI, covering burst capture review ranking, after-capture coaching summaries, empty-burst handling, guided calibration queue progress, calibration readiness next-scenario selection, calibration weight tuning, reviewed guidance-priority calibration, guidance stabilization, Personal Visual AI learning including local learning insights, creative interpretation plans, audited creative request payloads, health-gated OpenAI creative-provider request construction and response parsing, mobile-safe LensPilot Creative API request construction and response parsing, unsafe provider-output rejection, and customer correction reasons, local profile storage protection metadata, online-reference privacy policy, Wikimedia Commons and Openverse online-inspiration parsing, source-diverse online-result ranking, thumbnail cache eviction, calibration sample export, and reviewed calibration sample promotion.
- `LensPilotDirectorTests` on macOS CI, covering same-phone reference popup activation, popup selection into the full reference viewer, and returning from full reference view back to the popup.
- `AiBenchmarkTests` on macOS CI, covering the deterministic single-phone guidance benchmark suite.
- GitHub Actions `iOS app build`, covering the SwiftUI app target, local package dependency wiring, camera screen, reference picker, popup, and result review compilation.
- GitHub Actions backend server validation, covering the deployable `backend/server.mjs` wrapper around the mobile-safe Creative API handler and production-safety preflight checks.

## Latest Verification

- GitHub Actions run #56 passed AI fixture validation, Swift package tests, and the iOS app build for commit `be89215`.
- GitHub Actions run #57 passed AI fixture validation, Swift package tests, and the iOS app build for commit `c8f8ba6`.
- Local `.\scripts\test-all.ps1` passed JSON validation, TypeScript AI fixture validation, deterministic Target Preview validation, preview adjustment validation, after-capture coaching validation, six deterministic AI guidance benchmarks, Target Match calibration validation with readiness reporting, calibration readiness checklist validation, calibration promotion validation, reviewed importer readiness-summary validation, guided calibration queue validation, reviewed import normalization, Personal Visual AI validation, local learning insight validation, creative interpretation validation, creative payload audit validation, health-gated creative provider validation, OpenAI creative-provider payload and parser validation, mobile-safe LensPilot Creative API validation, backend Creative API server runtime validation, local profile storage validation, capture-feedback correction learning validation, single-phone AI diagnostics, and multi-provider public inspiration validation on Windows after Creative API wiring.
- Backend `npm test` passes the deployable server wrapper smoke suite without requiring a real OpenAI key.
- A live LensPilot Creative API smoke test reached OpenAI, but the provider completion is blocked by API billing credits: OpenAI returned `429 insufficient_quota` with `credit_balance_exhausted`. The backend now classifies this safely as `openai_credit_balance_exhausted` with `blockedByBilling: true` and `retryable: false`.
- Local `.\scripts\test-all.ps1` passed after adding safe provider-error classification for the backend Creative API and iOS Creative API provider.
- Swift package tests include regression coverage for same-phone provider diagnostics that classify exhausted credits and redact secret-looking tokens from OpenAI and LensPilot Creative API error messages.
- Swift package tests still need GitHub/macOS CI for this workspace because Windows does not have Swift/Xcode installed.

## Not Runnable Here

- `swift test` for the iOS Swift package, because the Swift toolchain and Xcode are not installed in this Windows workspace.

## Test Command

Run from the repository root:

```powershell
.\scripts\test-all.ps1
```

On macOS with Xcode/Swift installed, the same script will also run:

```bash
swift test
```

from `ios/Package`.

GitHub Actions additionally runs:

```bash
xcodebuild -project ios/App/LensPilotApp/LensPilotApp.xcodeproj -scheme LensPilotApp -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```
