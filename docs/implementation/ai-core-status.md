# LensPilot AI Core Status

This implementation completes the MVP AI control skeleton, not the final production intelligence. The current AI is deterministic and testable so the camera can work reliably before expensive models are introduced.

## Implemented Now

- Intent Engine: maps natural-language prompts into `ShotSpec`.
- Shot Planner: maps `ShotSpec + SceneState + DeviceCapability` into `ShotPlan`.
- Guidance Policy: selects one best next action using confidence, expected gain, priority, interaction cost, and safety qualifier.
- Target Match Engine: calculates normalized sub-scores and an overall match from measured scene values.
- Preview Safety Engine: enforces Natural, Enhanced, and Creative labels.
- Best-Shot Ranker: ranks burst candidates by sharpness, exposure, face quality, pose, composition, background, and intent match.
- Single-phone invariant: `ShotSpec.constraints.singlePhoneOnly` is required and true.
- Native Swift AI core: iOS now has on-device `SceneState`, `LensPilotAiCore`, `TargetMatchEngine`, `GuidancePolicy`, `PreviewSafetyEngine`, and `BestShotRanker` equivalents.
- App wiring: the iOS camera screen view model calls the native AI core and displays AI guidance plus Target Match from scene inputs.
- Live scene bridge: `FrameAnalyzer` output now maps `SceneDebugState` into native `SceneState`, and the camera screen refreshes AI guidance from analyzed live frames.
- Live quality metrics: `FrameAnalyzer` now derives horizon roll, face quality, pose, segmentation availability, and motion stability signals on-device.
- Reference-photo loop: selected library images stay on-device, appear in the camera popup, and open in the same-phone full reference viewer.
- Capture review loop: the app captures a plan-sized burst, ranks frame candidates on-device, and presents the best result plus alternatives.
- AI guidance benchmark suite: six deterministic calibration cases now cover cluttered portrait, tilted horizon, sunset highlight protection, motion blur, backlit face guidance, and ready-to-capture.
- Target Match calibration scaffold: scoring weights are explicit in Swift and TypeScript, and CI validates the calibration manifest.
- Calibration sample export: the single-phone camera UI can share anonymous `iphone_capture_candidate` JSON with prompt, scene, device, guidance, and Target Match data.
- Calibration promotion tool: reviewed candidates can be promoted into `iphone_capture` manifest entries only when single-phone privacy flags, domain labels, blind preference labels, and expected Target Match ranges are present.
- In-app blind review labeling: after capture, the same phone opens a score-free label sheet for domain, preferred fix, ranked weaknesses, reviewer count, and reviewed-sample export.
- Reviewed-sample importer: app exports can be normalized and appended to the calibration manifest only after single-phone privacy, blind-review, domain, and expected score-range validation passes.

## Not Yet Production AI

- No trained aesthetic model yet.
- No real iPhone target-match calibration dataset yet.
- No Core ML/TFLite production model bundle yet.
- No cloud VLM/LLM adapter yet.
- No generative preview engine yet.
- No user preference embedding yet.
- No blind-rater evaluation data yet.

## Why This Order

LensPilot must remain a reliable camera first. A deterministic AI core lets us prove the interaction loop, collect structured data, and measure whether guidance improves photos before adding model complexity.

## Required Next AI Work

1. Collect real portrait, landscape, sky, clutter, backlight, horizon, and motion samples from iPhone captures.
2. Add blind preference labels in the app, then import reviewed samples with `npm run calibration:import-reviewed`.
3. Tune benchmark thresholds and sub-score weights against blind preference tests.
4. Add optional cloud reasoning only for event-triggered creative interpretation.
