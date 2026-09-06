$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/activate-toolchain.ps1"
$lock = Get-Content "$repoRoot/toolchain.json" -Raw | ConvertFrom-Json
$version = (& moon version --all 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) { throw 'moon version failed' }
Write-Output $version
if (!$version.Contains("moonc $($lock.compiler)") -or !$version.Contains("moon $($lock.moon)")) {
    throw 'Toolchain differs from toolchain.json; run bootstrap and revalidate.'
}
& node --version
if ($LASTEXITCODE -ne 0) { throw 'Node.js is required for JS verification' }
