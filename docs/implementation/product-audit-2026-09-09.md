# LensPilot product, engineering and growth audit

Date: 2026-09-09. Baseline: `d63f72f`, branch `codex/android-camera-foundation`. Reviewed original development prompt, Android app, iOS camera/vision/core/director flow, shared contracts and validators, backend runtime, build workflows and calibration manifest. This is a repository and market audit, not a claim of exhaustive line-by-line verification or physical-device certification.

## Decision

Keep LensPilot in development/pilot testing. Its strongest intended position is a single-phone, privacy-first photography director that improves real captures. Current Android guidance is a rules-based prototype; current iOS scoring contains unvalidated proxies. Passing CI does not establish that either app takes better photographs than the built-in camera. The calibration manifest has zero reviewed real captures out of its 24-capture target.

## Findings ordered by priority

| Priority | Finding and evidence | Action/status |
| --- | --- | --- |
| P1 | Backend trusted the leftmost X-Forwarded-For value as a quota key (`backend/server.mjs`, clientRateLimitKey). A caller could change it to obtain fresh quota. | Reproduced with a failing HTTP regression, then fixed by using the TCP peer. New regression passes. Proxy peers now share quota; distributed per-user quotas remain necessary for scale. |
| P1 | iOS best-shot quality is synthesized from byte count and sequence index modulo 23 (`ios/Package/Sources/LensPilotCore/CaptureReview.swift`, candidate); TypeScript has the same proxy (`shared/typescript/src/ai-core.ts`). This is not measured sharpness. | Open release blocker: replace with image-derived per-frame metrics and blinded selection validation. Do not market current best-shot scores as measured quality. |
| P1 | iOS runAi can consume placeholderSceneState, including a fictional person, high scene confidence and movement permission, before live analysis (`ios/App/LensPilotApp/Camera/CameraScreenViewModel.swift`). | Open release blocker: distinguish unavailable observations, suppress scene-specific movement and scores until a fresh real frame arrives. |
| P1 | iOS camera configuration always picks builtInWideAngleCamera; planner recommendations do not physically select the recommended lens (`ios/Package/Sources/LensPilotCamera/CameraSessionController.swift`). | Open: capability-aware lens/exposure/focus application with physical-device validation. |
| P1 | Android has no subject recognition, arbitrary language understanding, target preview/scoring, best-shot selection, learned style or online inspiration. | Explicitly limited in app/docs. Do not call it full AI parity. Prioritize one measured intent-to-capture path before broad feature expansion. |
| P1 | Calibration is 0/24 real captures; existing guidance benchmark has six deterministic cases. | Open: complete seed calibration, then separate held-out device/scene evaluation. Twenty-four samples are a pilot gate, not population-level proof. |
| P2 | Main AI fixture validator reimplements portions of the algorithm instead of importing the actual TypeScript implementation (`shared/typescript/scripts/validate-ai-core.cjs`). | Open: introduce compilation/typecheck and tests against exported production code. Existing fixture passes have limited evidentiary value. |
| P2 | Rate-limit map retained distinct clients indefinitely. | Fixed: expiry cleanup and bounded shared overflow without evicting active limits. Regression covers overflow, retained limits and window expiry. |
| P2 | Android lacked a timer despite single-phone self-shot requirements. | Added off/3s/10s, cancel, duplicate-press protection and lifecycle guards. State-machine tests pass; physical capture timing still needs testing. |
| P2 | Android requests like 'more sky' were ignored unless they named a scene; negation could select the opposite intended mode. | Added supported composition/lighting requests and explicit unknown/negated-request fallback. This remains keyword handling, not unrestricted language understanding. |
| P2 | Root test-all omitted Android tests and recursively scanned ignored/generated JSON. | Fixed: JDK guidance/timer tests included; JSON scan uses non-ignored repository files. Android compilation/lint and device tests remain separate. |
| P2 | Debug APK signing identity is not deliberately persisted by the workflow. Fresh runners may produce APKs incompatible with a previously installed build. | Open distribution blocker: configure an owned stable signing identity/internal testing track. Do not solve upgrade failures by routinely asking users to delete app data. |
| P2 | No automated camera UI/lifecycle/device suite; iOS Vision requests use `.up` orientation and need rotation/mirroring evidence. | Open: test supported orientations and front/back cameras on hardware. Passing builds cannot establish these behaviors. |
| P2 | Existing docs list historical successes and historical provider billing failure without a current production probe. | This audit records current local results separately; live backend readiness, credits and provider performance were not checked or billed. |

## Implemented in this audit

Backend fixes above, a cancellable Android self-timer, request-specific photographic suggestions with honest fallback, Android system sharing for captured photos, Android core tests in the full local runner, and full-project CI triggering on the Android branch. Android version is now 0.3.0 (code 3). The timer and sharing operate on the same phone and do not introduce cloud storage, analytics, raw-frame uploads or extra permissions.

## Verification evidence

- Baseline local `scripts/test-all.ps1`: passed shared fixture/benchmark/calibration/privacy checks and backend tests. Swift skipped because unavailable on Windows.
- Added spoofing test: failed on the old backend, demonstrating the bypass.
- After fixes, local `scripts/test-all.ps1`: passed shared validators, backend suite including new spoofing/overflow regressions, and Java guidance/timer tests compiled with `--release 17`.
- Latest previously verified Android CI: [run 34257297363](https://github.com/chandra0814/aicamera/actions/runs/34257297363), commit d63f72f. This does NOT verify this audit's new changes.
- Latest previously verified main CI: [run 34176554683](https://github.com/chandra0814/aicamera/actions/runs/34176554683), commit 719319f. Swift, iOS build, AI fixtures and API container passed then.
- New APK build/lint, macOS/Swift, Docker and real-device behavior: not run locally. Must pass for the final commit before distributing an updated APK.
- Detailed coverage and manual scenarios: [release test matrix](release-test-matrix.md). No overall coverage percentage is claimed.

## Market comparison

Primary sources checked on 2026-09-09. Vendor feature descriptions establish competitive capability, not user satisfaction, market share or willingness to pay.

| Product | Evidence | Implication for LensPilot |
| --- | --- | --- |
| Google Pixel Camera Coach | Google describes Gemini-based contextual suggestions for framing, lighting and other camera choices. [Official overview](https://store.google.com/us/magazine/camera-coach?hl=en-US), [help](https://support.google.com/pixelcamera/answer/17367411?hl=en-GB). | Real-time coaching is already a competitor feature. Generic tips and an AI label are insufficient differentiation. |
| Samsung Shot suggestions | Samsung documents a machine-learning composition target for supported devices. [Official help](https://www.samsung.com/uk/support/mobile-devices/how-to-use-shot-suggestions/). | Composition guidance needs to be actionable and quick. Device support must be stated explicitly. |
| Adobe Lightroom mobile | Adobe demonstrates selective subject, sky and background edits with AI-assisted masking. [Official tutorial](https://www.adobe.com/learn/lightroom-cc/web/ai-assisted-masking-lightroom-mobile). | Avoid trying to build a complete editor before the capture loop is proven. Exporting a real photo is more immediately useful. |
| Halide | Process Zero emphasizes natural capture and photographic control; the product has continued into Mark III. [Process Zero](https://www.lux.camera/introducing-process-zero-for-iphone/), [Mark III](https://www.lux.camera/halide-mark-iii/). | Natural-looking output and clarity about processing can be positioning strengths; adding generative effects is not automatically progress. |

Recommended positioning (hypothesis): "Get the photo you intended, on your own phone, with private guidance before you shoot." Potential advantages to validate are support across ordinary Android/iOS devices, the on-screen reference comparison, actionable requests, and consented local personalization. These are proposed differentiators, not proven uniqueness or current feature parity.

## Growth experiments before monetization

1. Start with one cohort: novice creators shooting portraits and everyday food/product content on non-flagship phones. Interview 10-15 volunteers about missed shots and existing workarounds. Do not infer demand from competitor presence alone.
2. Run a two-week pilot with roughly 20-30 volunteers across phone tiers. Each takes matched stock-camera and LensPilot photos in randomized order. Use blinded comparisons with an explicit tie option. Keep calibration and evaluation photos separate.
3. Measure first-session completion (intent -> suggestion -> saved photo), time to first useful suggestion, advice helpfulness/rejection, photo preference, week-one return and crashes. Collect only consented aggregate feedback; no telemetry or photo collection has been added here.
4. Proposed engineering targets to test, not current results: useful local guidance within two seconds once preview starts, no unintended timer capture, no data loss in upgrades, and stable 15-minute camera sessions. Report latency by device and lighting condition, not one blended average.
5. Ship only when the pilot shows a meaningful preference for guided output without unacceptable capture delay or battery cost. Agree the minimum improvement before evaluation and report sample size/uncertainty. Twenty-four calibration captures alone cannot establish this.
6. After demonstrated value, test optional paid advanced coaching with explicit cloud quotas and cost measurement. Keep basic capture/offline guidance usable. Do not add subscriptions or paid acquisition until repeat use and provider unit costs are understood.

Do not add a social feed, cloud photo archive, video director, face identity, or generative editing in this phase. These expand cost and risk without resolving the current photography-quality gaps.

## Release dependencies

Stable Android signing/internal distribution, iOS signing/TestFlight access, store disclosures matching actual data flows, source attribution for online inspiration, supported-device/OS policy, crash recovery, and opt-in feedback/deletion flows are still required. [Android signing documentation](https://developer.android.com/studio/publish/app-signing) explains why signing identity matters for updates. For personal Play developer accounts created after 2023-11-13, Google's current production-access process requires at least 12 continuously opted-in testers for 14 days before applying; verify applicability in the actual account. [Official testing requirements](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en-GB).

This audit does not certify store acceptance, legal compliance, model quality, market size or revenue growth.
