param([switch]$Native)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
Push-Location $repoRoot
try {
    . "$PSScriptRoot/activate-toolchain.ps1"
    & moon run "$PSScriptRoot/doctor.mbtx"
    if ($LASTEXITCODE -ne 0) { throw 'Toolchain verification failed' }
    if ($Native) {
        $vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
        $installation = (& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath)
        if (!$installation) { throw 'Visual Studio C++ build tools and Windows SDK are required.' }
        Import-Module "$installation/Common7/Tools/Microsoft.VisualStudio.DevShell.dll"
        Enter-VsDevShell -VsInstallPath $installation -SkipAutomaticLocation -DevCmdArguments '-arch=x64 -host_arch=x64'
        $env:MOON_CC = 'cl'
        $env:VSLANG = '1033'
    }
    & moon fmt --check
    if ($LASTEXITCODE -ne 0) { throw 'Formatting failed; run mise run fmt' }
    $targets = if ($Native) { @('native') } else { @('wasm-gc', 'js') }
    foreach ($target in $targets) {
        & moon test --target $target --deny-warn
        if ($LASTEXITCODE -ne 0) { throw "Tests failed: $target" }
        & moon run examples/p0/frontend/app --target $target
        if ($LASTEXITCODE -ne 0) { throw "Contract-only FE failed: $target" }
        & "$PSScriptRoot/verify-types.ps1" -Target $target
    }
} finally {
    Pop-Location
}
