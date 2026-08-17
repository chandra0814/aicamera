# Calibration Protocol

LensPilot calibration must use single-phone captures only. A sample can include scene metrics, prompt text, device capability, anonymized capture metadata, and blind preference labels, but it must not include identity labels or require a second phone.

## Sample Format

Add calibration entries to `tests/calibration/target-match-calibration.json`.

- Use the in-app share control to export `sampleKind: "iphone_capture_candidate"` JSON from the current single-phone camera state.
- After capture, use the tag control to open the blind review sheet and export a reviewed `sampleKind: "iphone_capture"` JSON without exposing Target Match scores during labeling.
- Import reviewed app exports with `npm run calibration:import-reviewed -- --sample <reviewed-sample.json> --write` from `shared/typescript`.
- Promote a candidate to `sampleKind: "iphone_capture"` only after blind preference labels are added.
- Use `npm run calibration:promote -- --candidate <candidate.json> --sample-id <stable_id> --review-count 2 --preferred-guidance-reason <reason> --weaknesses background,lighting --write` from `shared/typescript` after review labels are ready.
- Include either inline `sceneState` and `deviceCapability`, or paths to JSON files.
- Include `captureMetadata.capturedAt` and `captureMetadata.deviceModel`.
- Include at least two blind preference reviews before using a sample to tune weights.
- Include a broad calibration `domain`: `portrait`, `landscape`, `lifestyle`, or `night`.
- Keep face/person data anonymous; do not add names, contacts, or identity labels.
- Keep `privacy.singlePhoneOnly: true`, `cloudAnalysisUsed: false`, `generativeEditsAllowed: false`, and `identityRecognitionAllowed: false`.

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

Reviewed exports created in the app already include the captured scene snapshot, anonymous device capability, blind preference labels, and expected Target Match ranges. Use the reviewed-sample importer to normalize and append them to `tests/calibration/target-match-calibration.json` before tuning.

The iOS app bundles this manifest as `target-match-calibration.json` and initializes the live `LensPilotAiCore` from its `targetMatchCalibration` weights. If the manifest is missing or violates single-phone validation rules, the app falls back to the standard deterministic weights rather than blocking camera use.
