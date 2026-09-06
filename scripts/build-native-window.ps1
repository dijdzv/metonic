[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repoRoot
try {
    & (Join-Path $repoRoot 'scripts/build-native-probe.ps1')
    if ($LASTEXITCODE -ne 0) { throw "native probe build failed with exit code $LASTEXITCODE" }
    . (Join-Path $repoRoot 'scripts/activate-toolchain.ps1')
    & moon build examples/p0/native_window --target native --release --deny-warn
    if ($LASTEXITCODE -ne 0) { throw "native window build failed with exit code $LASTEXITCODE" }
    $dll = Join-Path $repoRoot '.work/native-cargo/release/metonic_wgpu_probe.dll'
    $exe = Join-Path $repoRoot '_build/native/release/build/examples/p0/native_window/native_window.exe'
    if (-not (Test-Path -LiteralPath $dll -PathType Leaf)) { throw "Missing native bridge: $dll" }
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Missing native window executable: $exe" }
}
finally {
    Pop-Location
}
