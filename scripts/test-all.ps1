$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

Write-Host "== JSON parse validation =="
Get-ChildItem -Recurse -Filter *.json | ForEach-Object {
    $null = Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json
    Write-Host $_.FullName
}

Write-Host "`n== AI core fixture validation =="
Push-Location (Join-Path $repoRoot "shared/typescript")
npm run validate
Pop-Location

Write-Host "`n== Swift toolchain check =="
$swift = Get-Command swift -ErrorAction SilentlyContinue
if ($swift) {
    Push-Location (Join-Path $repoRoot "ios/Package")
    swift test
    Pop-Location
} else {
    Write-Host "Swift toolchain not found. Run 'swift test' from ios/Package on macOS/Xcode."
}
