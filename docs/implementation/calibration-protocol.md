# Calibration Protocol

LensPilot calibration must use single-phone captures only. A sample can include scene metrics, prompt text, device capability, anonymized capture metadata, and blind preference labels, but it must not include identity labels or require a second phone.

## Sample Format

Add calibration entries to `tests/calibration/target-match-calibration.json`.

- Use the in-app share control to export `sampleKind: "iphone_capture_candidate"` JSON from the current single-phone camera state.
- Promote a candidate to `sampleKind: "iphone_capture"` only after blind preference labels are added.
- Include either inline `sceneState` and `deviceCapability`, or paths to JSON files.
- Include `captureMetadata.capturedAt` and `captureMetadata.deviceModel`.
- Include at least two blind preference reviews before using a sample to tune weights.
- Keep face/person data anonymous; do not add names, contacts, or identity labels.

## Minimum Dataset

The current target is 24 real iPhone samples across:

- portrait
- landscape
- lifestyle
- night
- clutter
- backlight
- horizon
- motion blur

## Tuning Rule

Only change `targetMatchCalibration` weights when the sample set shows a repeated blind preference mismatch. Keep the benchmark suite green after each tuning change so deterministic regressions stay visible.
