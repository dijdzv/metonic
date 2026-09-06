[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repoRoot
try {
    . (Join-Path $repoRoot 'scripts/activate-toolchain.ps1')
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $installation = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($installation)) { throw 'Visual Studio installation was not found' }
    Import-Module (Join-Path $installation 'Common7/Tools/Microsoft.VisualStudio.DevShell.dll')
    Enter-VsDevShell -VsInstallPath $installation -SkipAutomaticLocation -DevCmdArguments '-arch=x64 -host_arch=x64'
    $env:MOON_CC = 'cl'
    $env:VSLANG = '1033'

    & cargo +1.98.1 build --manifest-path bridges/wgpu/Cargo.toml --locked --release --target-dir .work/native-cargo
    if ($LASTEXITCODE -ne 0) { throw "cargo build failed with exit code $LASTEXITCODE" }
    & moon build examples/p0/native_headless --target native --release --deny-warn
    if ($LASTEXITCODE -ne 0) { throw "moon native build failed with exit code $LASTEXITCODE" }

    $dll = Join-Path $repoRoot '.work/native-cargo/release/metonic_wgpu_probe.dll'
    $exe = Join-Path $repoRoot '_build/native/release/build/examples/p0/native_headless/native_headless.exe'
    if (-not (Test-Path -LiteralPath $dll -PathType Leaf)) { throw "Missing native bridge: $dll" }
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Missing native probe: $exe" }
}
finally {
    Pop-Location
}
