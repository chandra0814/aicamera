# LensPilot Android

Native Android camera foundation for Android 10+ (API 29). Kotlin, Jetpack Compose and CameraX keep camera preview, reference selection, capture, and review on one phone.

## Current scope

- Real CameraX preview and JPEG capture to Pictures/LensPilot.
- System photo picker for a reference; tappable thumbnail opens a full-screen viewer with uncropped image.
- Front/back camera switch, supported-camera flash, composition grid, last-photo review.
- Camera permission request, settings recovery, camera/capture errors, in-progress shutter lock.
- Opt-in local storage of grid preference; app backups disabled.
- No network permission, API credentials, or camera-frame uploads.

This is an Android camera foundation, not full iOS AI parity. Shared Target Match scoring, scene analysis, capture coaching, adaptive learning, online reference providers, and calibration exports are not yet ported. Remembering a grid preference is not model training. Settings report the disconnected AI/provider state.

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

No physical Android device testing has been performed in the Windows workspace.

Architecture sources: [CameraX](https://developer.android.com/media/camera/camerax/architecture), [Compose BOM](https://developer.android.com/develop/ui/compose/bom).
