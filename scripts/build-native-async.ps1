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
    # Remove only the package stub object so included C/header updates are reflected.
    $stubObject = Join-Path $repoRoot '_build/native/release/build/examples/p0/native_async/bridge.obj'
    if (Test-Path -LiteralPath $stubObject -PathType Leaf) { Remove-Item -LiteralPath $stubObject -Force }
    & moon build examples/p0/native_async --target native --release --deny-warn
    if ($LASTEXITCODE -ne 0) { throw "native async build failed with exit code $LASTEXITCODE" }
    $exe = Join-Path $repoRoot '_build/native/release/build/examples/p0/native_async/native_async.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Missing native async executable: $exe" }
}
finally { Pop-Location }
