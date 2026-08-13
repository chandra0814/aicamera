# Next Build Steps

## Immediate iOS Work

1. Open `ios/Package` from Xcode on macOS and run the `LensPilotCoreTests` test target.
2. Collect real portrait, landscape, sky, clutter, backlight, horizon, and motion samples from iPhone captures.
3. Calibrate the on-device metric weights against those real samples and blind preferences.
4. Add `NSMicrophoneUsageDescription` later, when voice input is wired.

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
- `scripts/test-all.ps1` now fails on external command failures instead of continuing after a broken `npm` or Swift run.

## Single-Phone Verification Checklist

- The camera preview, reference popup, full reference viewer, guidance, capture, and result review all run on one device.
- Front camera self-shot mode never assumes a second person or device.
- Reference photo viewing does not stop the live camera session.
- Cloud is not required for camera preview, basic ShotSpec, basic ShotPlan, guidance, capture, or best-shot selection.

## MVP Boundary

Do not build video director, social features, cloud storage, generative editing, or multi-device capture until the single-phone photo loop produces measurably better images.
