[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot 'ci-scope.ps1'

function Assert-Scope {
    param(
        [string] $Name,
        [string[]] $Paths,
        [bool] $Expected,
        [switch] $Full
    )

    $arguments = @{ ChangedPaths = $Paths }
    if ($Full) { $arguments = @{ Full = $true } }
    $actual = (& $scriptPath @arguments | Select-Object -Last 1).Trim()
    if ($actual -ne ([string]$Expected).ToLowerInvariant()) {
        throw "Scope test '$Name' expected $Expected but got '$actual'."
    }
}

function Assert-Throws {
    param(
        [string] $Name,
        [hashtable] $Arguments
    )

    $thrown = $false
    try {
        & $scriptPath @Arguments | Out-Null
    } catch {
        $thrown = $true
    }
    if (-not $thrown) {
        throw "Scope test '$Name' expected an exception."
    }
}

Assert-Scope 'docs-only' @('README.md', 'docs/guide.md') $false
Assert-Scope 'uppercase-docs' @('DOCS/guide.md') $false
Assert-Scope 'license-mit' @('LICENSE-MIT') $false
Assert-Scope 'deleted-docs' @('CONTRIBUTING.md', 'CHANGELOG.md') $false
Assert-Scope 'source' @('src/main.mbt') $true
Assert-Scope 'workflow' @('.github/workflows/verify.yml') $true
Assert-Scope 'mise' @('mise.toml') $true
Assert-Scope 'toolchain' @('scripts/bootstrap.ps1', 'toolchain.json') $true
Assert-Scope 'unknown' @('notes/example.txt') $true
Assert-Scope 'docs-and-code' @('docs/guide.md', 'src/main.mbt') $true
Assert-Scope 'deleted-old-source' @('src/removed.mbt') $true
Assert-Scope 'renamed-old-source' @('src/old-name.mbt') $true
Assert-Scope 'source-to-docs-rename' @('src/old-name.mbt', 'docs/new-name.md') $true
Assert-Scope 'empty' @() $true
Assert-Scope 'full' @() $true -Full
Assert-Throws 'missing-mode' @{}
Assert-Throws 'one-sided-sha' @{ BaseSha = ('a' * 40) }
Assert-Throws 'invalid-sha' @{ BaseSha = 'invalid'; HeadSha = ('b' * 40) }
Assert-Throws 'mode-conflict' @{ ChangedPaths = @('README.md'); BaseSha = ('a' * 40); HeadSha = ('b' * 40) }

Write-Output 'ci-scope tests passed.'
