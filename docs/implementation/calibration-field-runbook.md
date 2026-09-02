# Calibration Field Runbook

Use this when the code and CI are green and the next step is real iPhone calibration. The goal is 24 reviewed single-phone captures: three each for portrait, landscape, sky, clutter, backlight, horizon, motion, and night.

## Before Capture

Run from `shared/typescript`:

```powershell
npm run calibration:session-plan
npm run calibration:readiness
```

The session plan lists every required capture slot and the next missing scenario. If you want a local checklist file for the field session:

```powershell
npm run calibration:session-plan -- --out ..\..\docs\implementation\calibration-session-plan.generated.md
```

Do not commit generated field notes unless they are intentionally reviewed. The source of truth stays `tests/calibration/target-match-calibration.json`.

## On The iPhone

1. Open LensPilot on the same iPhone that will capture the photos.
2. Open AI Diagnostics and confirm calibration readiness still shows the missing capture count and next scenario.
3. Select the next calibration scenario from the in-app queue.
4. If using a reference, select it on the same phone and confirm it appears as the on-screen popup.
5. Tap the popup and confirm the same-phone full reference viewer opens, then return to the camera.
6. Capture the guided burst, review the selected real result, and open the blind review sheet.
7. Export the reviewed `iphone_capture` JSON from the share control.

Keep calibration offline and single-phone: no second device, no raw photo storage in JSON, no live-frame uploads, no identity labels, no EXIF GPS, and no generative edits. Optional online inspiration can guide what the user wants before capture, but calibration exports must contain only prompt/scene/device/review summaries.

## Import Reviewed Exports

Copy each reviewed JSON export to the repo machine, then run from `shared/typescript`:

```powershell
npm run calibration:import-reviewed -- --sample <reviewed-sample.json> --write
npm run calibration:readiness
npm run validate
```

Repeat until readiness reports `ready`, 24/24 reviewed captures, no missing domains, and no missing scenarios.

## After 24 Reviewed Captures

Run the full repo check:

```powershell
..\..\scripts\test-all.ps1
```

Only tune Target Match weights after the 24 reviewed captures show a repeated blind-preference mismatch. Keep safety, confidence, and expected-gain gates stronger than learned guidance boosts.
