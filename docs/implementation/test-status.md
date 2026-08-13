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
- `AiBenchmarkTests` on macOS CI, covering the deterministic single-phone guidance benchmark suite.
- GitHub Actions `iOS app build`, covering the SwiftUI app target, local package dependency wiring, camera screen, reference picker, popup, and result review compilation.

## Latest Verification

- GitHub Actions run #16 passed AI fixture validation, Swift package tests, and the iOS app build for commit `c31b69b`.
- Local `.\scripts\test-all.ps1` passed JSON validation, TypeScript AI fixture validation, and six deterministic AI guidance benchmarks on Windows.
- The new Swift benchmark test is queued for the next macOS CI run because this Windows workspace does not have Swift/Xcode installed.

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
