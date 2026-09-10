$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

Write-Host "== JSON parse validation =="
$jsonFiles = git ls-files --cached --others --exclude-standard -- '*.json'
if ($LASTEXITCODE -ne 0) { throw "Could not enumerate repository JSON files." }
$jsonFiles | Sort-Object -Unique | ForEach-Object {
    node -e "JSON.parse(require('node:fs').readFileSync(process.argv[1], 'utf8'))" (Join-Path $repoRoot $_)
    if ($LASTEXITCODE -ne 0) { throw "Invalid JSON: $_" }
    Write-Host $_
}

Write-Host "`n== AI core fixture validation =="
Push-Location (Join-Path $repoRoot "shared/typescript")
npm test
if ($LASTEXITCODE -ne 0) {
    throw "Production TypeScript tests failed. Run npm ci in shared/typescript if dependencies are missing."
}
npm run validate
if ($LASTEXITCODE -ne 0) {
    throw "AI core fixture validation failed with exit code $LASTEXITCODE."
}
Pop-Location

Write-Host "`n== Backend creative API server validation =="
Push-Location (Join-Path $repoRoot "backend")
npm test
if ($LASTEXITCODE -ne 0) {
    throw "Backend creative API server validation failed with exit code $LASTEXITCODE."
}
Pop-Location

Write-Host "`n== Android core tests (JDK required) =="
& (Join-Path $PSScriptRoot "test-android-core.ps1")
Write-Host "Android APK build/lint and physical device tests are separate from these JVM checks."

Write-Host "`n== Swift toolchain check =="
$swift = Get-Command swift -ErrorAction SilentlyContinue
if ($swift) {
    Push-Location (Join-Path $repoRoot "ios/Package")
    swift test
    if ($LASTEXITCODE -ne 0) {
        throw "Swift package tests failed with exit code $LASTEXITCODE."
    }
    Pop-Location
} else {
    Write-Host "Swift toolchain not found. Run 'swift test' from ios/Package on macOS/Xcode."
}
