param([string]$JavaHome = $env:JAVA_HOME)
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$javac = Get-Command javac -ErrorAction SilentlyContinue
if ($JavaHome -and (Test-Path (Join-Path $JavaHome "bin/javac.exe"))) {
    $compiler = Join-Path $JavaHome "bin/javac.exe"
} elseif ($javac) {
    $compiler = $javac.Source
} else {
    $installed = Get-ChildItem -Path "$env:ProgramFiles/Java/*/bin/javac.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (!$installed) { throw "Android core tests require a JDK. Set JAVA_HOME or add javac to PATH." }
    $compiler = $installed.FullName
}
$runtime = Join-Path (Split-Path -Parent $compiler) "java.exe"
if (!(Test-Path $runtime)) { $runtime = Join-Path (Split-Path -Parent $compiler) "java" }
$output = Join-Path $repoRoot "android/.test-output"
$source = Join-Path $repoRoot "android/app/src/main/java/ai/lenspilot/android"
& $compiler --release 17 -d $output (Join-Path $source "GuidanceEngine.java") (Join-Path $source "CaptureTimer.java") (Join-Path $repoRoot "android/tests/GuidanceEngineTest.java")
if ($LASTEXITCODE -ne 0) { throw "Android core compilation failed." }
& $runtime -cp $output GuidanceEngineTest
if ($LASTEXITCODE -ne 0) { throw "Android core tests failed." }
