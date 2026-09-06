[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    & git diff --cached --check
    if ($LASTEXITCODE -ne 0) {
        throw "git diff --cached --check failed with exit code ${LASTEXITCODE}."
    }

    $staged = @(& git -c core.quotepath=false diff --cached --name-only --no-renames 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git diff --cached --name-only failed with exit code ${LASTEXITCODE}: $($staged -join [Environment]::NewLine)"
    }
    $staged = @($staged | ForEach-Object { [string]$_ } | Where-Object { $_.Length -gt 0 })

    $verifyDocs = Join-Path $repoRoot 'scripts/verify-docs.ps1'
    if (@($staged | Where-Object { $_ -match '(?i)\.md$' }).Count -gt 0) {
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $verifyDocs
        if ($LASTEXITCODE -ne 0) {
            throw "verify-docs.ps1 failed with exit code ${LASTEXITCODE}."
        }
    }

    $moonFiles = @($staged | Where-Object {
        $_ -match '(?i)(?:\.mbt|\.mbti|(?:^|/)(?:moon\.(?:mod|pkg)(?:\.json)?))$'
    })
    if ($moonFiles.Count -gt 0) {
        $moonScript = Join-Path $repoRoot 'scripts/moon.ps1'
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $moonScript fmt --check
        if ($LASTEXITCODE -ne 0) {
            throw "moon.ps1 fmt --check failed with exit code ${LASTEXITCODE}."
        }
    }

    Write-Output 'Pre-commit checks passed.'
}
finally {
    Pop-Location
}
