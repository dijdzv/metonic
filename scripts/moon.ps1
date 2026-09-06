param([Parameter(ValueFromRemainingArguments = $true)][string[]]$MoonArguments)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/activate-toolchain.ps1"
& "$env:MOON_HOME/bin/moon.exe" @MoonArguments
exit $LASTEXITCODE
