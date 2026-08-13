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
- Swift package tests passed in GitHub Actions run #14 for commit `9fa7f2c`.
- The iOS app build still failed in run #14, but the compiler diagnostic was hidden inside clipped Xcode output. The workflow now tees `xcodebuild.log`, prints focused compiler errors, and uploads the full log artifact on every iOS build.

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
