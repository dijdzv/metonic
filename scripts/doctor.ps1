$ErrorActionPreference = 'Stop'
$version = (& moon version --all 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) { throw 'moon version failed' }
Write-Output $version
if ($version -notmatch 'moonc v0\.7\.2\+938b1f804' -or $version -notmatch 'moon 0\.1\.20260119') {
    throw 'Toolchain differs from the P0 baseline; revalidate and update the recorded versions deliberately.'
}
& node --version
if ($LASTEXITCODE -ne 0) { throw 'Node.js is required for JS verification' }
