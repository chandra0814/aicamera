# LensPilot Android

Native Android camera foundation for Android 10+ (API 29). Kotlin, Jetpack Compose and CameraX keep camera preview, reference selection, capture, and review on one phone.

## Current scope

- Real CameraX preview and JPEG capture to Pictures/LensPilot.
- System photo picker for a reference; tappable thumbnail opens a full-screen viewer with uncropped image.
- Front/back camera switch, supported-camera flash, composition grid, last-photo review.
- Camera permission request, settings recovery, camera/capture errors, in-progress shutter lock.
- Opt-in local storage of grid preference; app backups disabled.
- Visible local shot ideas for general, portrait, landscape, food, and night photography. The ideas dialog accepts a short request and matches supported scene keywords; unsupported requests fall back to the selected scene.
- Live on-device luminance checks suggest brighter/softer light or night stabilization. Consecutive readings prevent flickering; old readings expire. Frames are closed immediately after analysis and are not stored or uploaded.
- No network permission, API credentials, or camera-frame uploads.

This is not full iOS AI parity. Local guidance uses photographic rules and average frame brightness, not a generative model. It does not recognize subjects, semantically understand arbitrary requests, or analyze reference images. Shared Target Match scoring, subject analysis, adaptive learning, online reference providers, and calibration exports are not yet ported. Remembering a grid preference is not model training.

## Build

Open this directory in Android Studio, use JDK 17, Android SDK 35 and Gradle 8.11.1. There is no checked-in wrapper yet; with Gradle installed:

```sh
gradle :app:assembleDebug :app:lintDebug
```

The LensPilot Android GitHub workflow runs the same checks and uploads the debug APK as `lenspilot-android-debug`. This is a development APK, not a Play Store release. After a successful build, install on your Android phone using Android Studio or `adb install -r app/build/outputs/apk/debug/app-debug.apk`.

## Device acceptance checks

1. Deny camera permission, then grant it through settings and return. Preview must recover.
2. Switch cameras; check unsupported cameras and front-camera flash behavior.
3. Select, replace and remove a reference. Tap the thumbnail, check the entire image, dismiss it, then capture on the same phone.
4. Capture once, confirm the shutter locks during save, open the last-photo preview, and check the saved file in Pictures/LensPilot.
5. Background/resume and rotate the phone. Confirm preview orientation and capture remain correct.
6. Toggle remembering grid preference, restart, and verify opt-out removes the saved preference.
7. Check narrow screens, landscape, large font sizes, TalkBack labels, and denied/revoked photo access.
8. Confirm a shot idea appears immediately. Open the lightbulb control, select each scene, try supported keywords, and cycle ideas. With a reference selected, cycle to its comparison idea.
9. Point at dark and bright areas for at least two seconds and confirm light advice changes. Background the app or open the photo viewer; old light readings must clear. On short landscape screens the camera and controls scroll instead of overlapping.

The pure Java guidance tests can run without an Android SDK:

```sh
javac -d /tmp/lenspilot-guidance app/src/main/java/ai/lenspilot/android/GuidanceEngine.java tests/GuidanceEngineTest.java
java -cp /tmp/lenspilot-guidance GuidanceEngineTest
```

These tests cover unsigned luminance, padded rows/pixel strides, buffer offsets, empty frames, keyword priority, manual fallback, and idea cycling. The Android workflow runs them before publishing the APK.

No physical Android device testing has been performed in the Windows workspace.

Architecture sources: [CameraX](https://developer.android.com/media/camera/camerax/architecture), [Compose BOM](https://developer.android.com/develop/ui/compose/bom).
