# Milestone 1: iOS Camera + Capability + Scene Debug

This milestone starts the LensPilot MVP as a single-phone experience. The same phone must own the live camera session, analyze frames, show the reference popup, guide the user, capture the burst, rank the result, and present the final image.

## Current Scaffold

- `ios/Package`: Swift package with core contracts, camera runtime, vision debug models, and director UI state.
- `schemas`: JSON Schema contracts for `ShotSpec`, `DeviceCapability`, and `ReferencePhotoState`.
- `shared/typescript`: TypeScript contract mirrors for backend/shared tooling.
- `tests/fixtures`: Sample ShotSpec and reference popup state.

## iOS Build Targets

- `LensPilotCore`: data contracts and single-phone invariants.
- `LensPilotCamera`: AVFoundation session and device capability profiler.
- `LensPilotVision`: scene debug model contracts.
- `LensPilotDirector`: one-phone director state and reference popup UI.

## Next Implementation Tasks

1. Create an Xcode iOS app target that imports the Swift package.
2. Add a `UIViewRepresentable` camera preview layer around `AVCaptureVideoPreviewLayer`.
3. Connect `CameraSessionController` to app lifecycle and camera permission flow.
4. Add `AVCaptureVideoDataOutput` frame sampling for Vision person detection and exposure metrics.
5. Render `CameraOverlayChrome` over the live camera preview.
6. Add reference-photo picker and bind selected assets to `ReferencePhotoState`.
7. Add capture and burst capture using `AVCapturePhotoOutput`.

## Single-Phone Rules

- Do not introduce a companion device requirement.
- Do not assume a second photographer or remote screen.
- For self-photos, use front camera, voice prompts, haptics, countdown, auto-capture, and on-screen overlays on the same phone.
- Cloud AI may enhance optional reasoning or Creative preview, but live camera analysis must stay usable without cloud.
