# Test Status

## Runnable In This Workspace

- JSON parse validation for all `.json` files.
- `npm run validate` inside `shared/typescript`, covering:
  - `singlePhoneOnly` invariant
  - identity recognition disabled
  - telephoto lens recommendation from fixture device capabilities
  - normalized Target Match
  - safety-qualified movement guidance
  - deterministic AI guidance benchmarks with manifest-derived guidance calibration
  - Target Match calibration manifest validation, including candidate-sample privacy checks
  - reviewed candidate promotion into labeled `iphone_capture` calibration samples
  - reviewed app export normalization before manifest import
  - guidance stabilizer checks for immediate opposite-action suppression and completed-action memory
  - Personal Visual AI validation for consent-gated learning, small personalization boosts, and online-reference privacy boundaries
  - Wikimedia Commons online-inspiration request construction and public image response parsing
- `LensPilotVisionTests` on macOS CI, covering the `SceneDebugState` to native `SceneState` bridge and on-device quality metric mapping.
- `LensPilotCoreTests` on macOS CI, covering burst capture review ranking, empty-burst handling, calibration weight tuning, reviewed guidance-priority calibration, guidance stabilization, Personal Visual AI learning, online-reference privacy policy, Wikimedia Commons online-inspiration parsing, calibration sample export, and reviewed calibration sample promotion.
- `AiBenchmarkTests` on macOS CI, covering the deterministic single-phone guidance benchmark suite.
- GitHub Actions `iOS app build`, covering the SwiftUI app target, local package dependency wiring, camera screen, reference picker, popup, and result review compilation.

## Latest Verification

- GitHub Actions run #30 passed AI fixture validation, Swift package tests, and the iOS app build for commit `a3c284c`.
- Local `.\scripts\test-all.ps1` passed JSON validation, TypeScript AI fixture validation, six deterministic AI guidance benchmarks, Target Match calibration validation, calibration promotion validation, and reviewed import normalization on Windows.
- Swift package tests still need GitHub/macOS CI for this workspace because Windows does not have Swift/Xcode installed.

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
