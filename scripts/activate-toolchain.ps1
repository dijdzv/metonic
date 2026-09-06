$repoRoot = Split-Path $PSScriptRoot -Parent
$env:MOON_HOME = Join-Path $repoRoot '.tools/moonbit'
if (!(Test-Path -LiteralPath "$env:MOON_HOME/bin/moon.exe")) {
    throw 'Run mise run bootstrap first.'
}
$env:PATH = "$env:MOON_HOME/bin;$env:PATH"
