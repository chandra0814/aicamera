# Next Build Steps

## Immediate iOS Work

1. Open `ios/Package` from Xcode on macOS and run the `LensPilotCoreTests` test target.
2. Calibrate the on-device metric weights against real portrait and landscape samples.
3. Add `NSMicrophoneUsageDescription` later, when voice input is wired.

## Completed Single-Phone Runtime Work

- `LensPilotApp.xcodeproj` now builds the same-phone SwiftUI app target against the local Swift package.
- The app target includes camera and photo-library permission strings in `Support/Info.plist`.
- GitHub Actions now builds the iOS app target on macOS in addition to Swift package tests.
- `AVCaptureVideoDataOutput` now feeds `FrameAnalyzer` through the camera screen frame-analysis coordinator.
- `SceneDebugState` now maps into native `SceneState`, so the on-device AI guidance can refresh from live frames instead of only using placeholder state.
- `FrameAnalyzer` now produces on-device horizon roll, face quality, pose, segmentation availability, and motion stability metrics for the AI core.
- Reference photos now use a real `PhotosPicker` flow; the selected image appears as the camera popup and opens in the full same-phone reference viewer.
- Capture now follows the plan's burst count, ranks the captured frames with the on-device best-shot ranker, and shows a same-phone result review.
- The live scene bridge is covered by `LensPilotVisionTests`.

## Single-Phone Verification Checklist

- The camera preview, reference popup, full reference viewer, guidance, capture, and result review all run on one device.
- Front camera self-shot mode never assumes a second person or device.
- Reference photo viewing does not stop the live camera session.
- Cloud is not required for camera preview, basic ShotSpec, basic ShotPlan, guidance, capture, or best-shot selection.

## MVP Boundary

Do not build video director, social features, cloud storage, generative editing, or multi-device capture until the single-phone photo loop produces measurably better images.
