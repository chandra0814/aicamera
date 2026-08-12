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

## Not Yet Production AI

- No trained aesthetic model yet.
- No calibrated target-match dataset yet.
- No Core ML/TFLite production model bundle yet.
- No cloud VLM/LLM adapter yet.
- No generative preview engine yet.
- No user preference embedding yet.
- No blind-rater evaluation data yet.

## Why This Order

LensPilot must remain a reliable camera first. A deterministic AI core lets us prove the interaction loop, collect structured data, and measure whether guidance improves photos before adding model complexity.

## Required Next AI Work

1. Feed real iOS `SceneDebugState` into native `SceneState` instead of the current placeholder scene.
2. Add on-device pose, segmentation, horizon, and exposure metrics.
3. Build a benchmark set for portrait, landscape, sky, clutter, backlight, and horizon problems.
4. Calibrate sub-score weights against blind preference tests.
5. Add optional cloud reasoning only for event-triggered creative interpretation.
