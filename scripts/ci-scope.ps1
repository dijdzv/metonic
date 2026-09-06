[CmdletBinding()]
param(
    [string[]] $ChangedPaths,
    [string] $BaseSha,
    [string] $HeadSha,
    [switch] $Full,
    [switch] $WriteGitHubOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-DocsOnlyPath {
    param([Parameter(Mandatory)][string] $Path)

    $normalized = $Path.Replace('\', '/')
    $rootDocs = @(
        'README.md', 'AGENTS.md', 'DESIGN.md', 'CONTRIBUTING.md',
        'CHANGELOG.md', 'LICENSE', 'LICENSE-MIT', 'LICENSE-APACHE'
    )
    foreach ($allowed in $rootDocs) {
        if ($normalized.Equals($allowed, [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $normalized -match '(?i)^docs/.+\.md$'
}

function Get-ChangedPathsFromGit {
    param(
        [Parameter(Mandatory)][string] $Base,
        [Parameter(Mandatory)][string] $Head
    )

    if ($Base -notmatch '^[0-9a-fA-F]{40}$' -or $Head -notmatch '^[0-9a-fA-F]{40}$') {
        throw 'BaseSha and HeadSha must each be exactly 40 hexadecimal characters.'
    }

    $gitOutput = @(& git diff --name-only --no-renames $Base $Head 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git diff failed with exit code ${LASTEXITCODE}: $($gitOutput -join [Environment]::NewLine)"
    }
    return @($gitOutput | ForEach-Object { [string]$_ } | Where-Object { $_.Length -gt 0 })
}

$hasChangedPaths = $null -ne $ChangedPaths
$hasBase = -not [String]::IsNullOrWhiteSpace($BaseSha)
$hasHead = -not [String]::IsNullOrWhiteSpace($HeadSha)
$hasShaMode = $hasBase -or $hasHead

if ($Full -and ($hasChangedPaths -or $hasShaMode)) {
    throw 'Full cannot be combined with ChangedPaths, BaseSha, or HeadSha.'
}
if ($hasShaMode -and (-not $hasBase -or -not $hasHead)) {
    throw 'BaseSha and HeadSha must be supplied together.'
}
if ($hasChangedPaths -and $hasShaMode) {
    throw 'ChangedPaths cannot be combined with BaseSha or HeadSha.'
}
if (-not $Full -and -not $hasChangedPaths -and -not $hasShaMode) {
    throw 'Supply ChangedPaths, BaseSha and HeadSha, or Full.'
}

$fullRequired = $false
if ($Full) {
    $fullRequired = $true
} else {
    $paths = @(
        if ($hasShaMode) { Get-ChangedPathsFromGit -Base $BaseSha -Head $HeadSha }
        else { $ChangedPaths }
    )
    if ($paths.Count -eq 0) {
        $fullRequired = $true
    } else {
        $fullRequired = @($paths | Where-Object { -not (Test-DocsOnlyPath $_) }).Count -gt 0
    }
}

$result = if ($fullRequired) { 'true' } else { 'false' }
if ($WriteGitHubOutput) {
    if ([String]::IsNullOrWhiteSpace($env:GITHUB_OUTPUT)) {
        throw 'WriteGitHubOutput requires GITHUB_OUTPUT.'
    }
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "full=$result" -Encoding utf8
}
Write-Output $result
