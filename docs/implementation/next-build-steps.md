# Next Build Steps

## Immediate iOS Work

1. Open `ios/Package` from Xcode on macOS and run the `LensPilotCoreTests` test target.
2. Create an iOS app project named `LensPilotApp`.
3. Add the Swift package as a local package dependency.
4. Add the files under `ios/App/LensPilotApp` to the app target.
5. Add camera permission text to `Info.plist`:
   - `NSCameraUsageDescription`
   - `NSPhotoLibraryUsageDescription`
   - `NSMicrophoneUsageDescription` later, when voice input is wired.
6. Replace `activateMockReference()` with a real `PhotosPicker` flow.
7. Add live result review after capture, using the ranked burst output.
8. Add more on-device metrics for horizon roll, face quality, pose, segmentation, and motion stability.

## Completed Single-Phone Runtime Work

- `AVCaptureVideoDataOutput` now feeds `FrameAnalyzer` through the camera screen frame-analysis coordinator.
- `SceneDebugState` now maps into native `SceneState`, so the on-device AI guidance can refresh from live frames instead of only using placeholder state.
- The live scene bridge is covered by `LensPilotVisionTests`.

## Single-Phone Verification Checklist

- The camera preview, reference popup, full reference viewer, guidance, capture, and result review all run on one device.
- Front camera self-shot mode never assumes a second person or device.
- Reference photo viewing does not stop the live camera session.
- Cloud is not required for camera preview, basic ShotSpec, basic ShotPlan, guidance, capture, or best-shot selection.

## MVP Boundary

Do not build video director, social features, cloud storage, generative editing, or multi-device capture until the single-phone photo loop produces measurably better images.
