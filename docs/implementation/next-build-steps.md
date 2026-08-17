# Next Build Steps

## Immediate iOS Work

1. Open `ios/Package` from Xcode on macOS and run the `LensPilotCoreTests` test target.
2. Use the in-app share control to export `iphone_capture_candidate` JSON for portrait, landscape, sky, clutter, backlight, horizon, and motion samples.
3. Add blind preference labels from the in-app tag control, then import reviewed app exports with `npm run calibration:import-reviewed -- --sample <reviewed-sample.json> --write`.
4. Calibrate the on-device metric weights and guidance priorities against those reviewed samples; the app now loads the bundled manifest into `LensPilotAiCore`.
5. Add `NSMicrophoneUsageDescription` later, when voice input is wired.

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
- The live scene bridge is covered by `LensPilotVisionTests`.
- The AI guidance benchmark suite now covers cluttered portrait, tilted horizon, sunset highlight protection, motion blur, backlit face guidance, and ready-to-capture.
- Target Match calibration weights are explicit in Swift and TypeScript, with a CI-validated calibration manifest and protocol.
- The single-phone camera UI can share anonymous calibration candidate JSON for real-capture scoring.
- Reviewed candidate promotion is now scripted and validated before samples can gate Target Match calibration.
- The single-phone app can label the latest captured sample in a score-free blind review sheet and export reviewed calibration JSON.
- Reviewed app exports can now be normalized and appended to the calibration manifest with a validated import command.
- The app target bundles `target-match-calibration.json`, validates its single-phone invariants, and applies its Target Match weights to the live on-device AI core with a safe fallback to defaults.
- Reviewed `iphone_capture` labels now produce small domain-aware guidance boosts, so blind preferences can influence the next selected action without bypassing safety or confidence gates.
- `scripts/test-all.ps1` now fails on external command failures instead of continuing after a broken `npm` or Swift run.
- The live director now stabilizes one-action-at-a-time guidance with TTL, opposite-action suppression, and short completed-action memory to reduce frame-to-frame instruction flipping.

## Single-Phone Verification Checklist

- The camera preview, reference popup, full reference viewer, guidance, capture, and result review all run on one device.
- Front camera self-shot mode never assumes a second person or device.
- Reference photo viewing does not stop the live camera session.
- Cloud is not required for camera preview, basic ShotSpec, basic ShotPlan, guidance, capture, or best-shot selection.

## MVP Boundary

Do not build video director, social features, cloud storage, generative editing, or multi-device capture until the single-phone photo loop produces measurably better images.
