# Test Status

## Runnable In This Workspace

- JSON parse validation for all `.json` files.
- `npm run validate` inside `shared/typescript`, covering:
  - `singlePhoneOnly` invariant
  - identity recognition disabled
  - telephoto lens recommendation from fixture device capabilities
  - normalized Target Match
  - safety-qualified movement guidance
- `LensPilotVisionTests` on macOS CI, covering the `SceneDebugState` to native `SceneState` bridge and on-device quality metric mapping.
- `LensPilotCoreTests` on macOS CI, covering burst capture review ranking and empty-burst handling.
- GitHub Actions `iOS app build`, covering the SwiftUI app target, local package dependency wiring, camera screen, reference picker, popup, and result review compilation.

## Latest Verification

- Local `.\scripts\test-all.ps1` passed JSON validation and TypeScript AI fixture validation on Windows.
- Swift package tests passed in GitHub Actions run #15 for commit `964f993`.
- The iOS app build failed in run #15 because Xcode could not type-check the motion frame-delta expression in `FrameAnalyzer.swift` quickly enough. That expression has been split into explicit loop steps for the next CI run.

## Not Runnable Here

- `swift test` for the iOS Swift package, because the Swift toolchain and Xcode are not installed in this Windows workspace.

## Test Command

Run from the repository root:

```powershell
.\scripts\test-all.ps1
```

On macOS with Xcode/Swift installed, the same script will also run:

```bash
swift test
```

from `ios/Package`.

GitHub Actions additionally runs:

```bash
xcodebuild -project ios/App/LensPilotApp/LensPilotApp.xcodeproj -scheme LensPilotApp -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```
