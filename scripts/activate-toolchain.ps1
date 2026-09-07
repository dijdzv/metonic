$repoRoot = Split-Path $PSScriptRoot -Parent
$env:MOON_HOME = Join-Path $repoRoot '.tools/moonbit'
if (!(Test-Path -LiteralPath "$env:MOON_HOME/bin/moon.exe")) {
    throw 'Run mise run bootstrap first.'
}
$env:PATH = "$env:MOON_HOME/bin;$env:PATH"
$env:MBT_WGPU_NATIVE_ROOT = Join-Path $repoRoot '.work/wgpu-assets'
$env:MBT_WGPU_LINK_MODE = 'static'
