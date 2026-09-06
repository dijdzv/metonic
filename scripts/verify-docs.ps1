[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$tracked = @(& git ls-files '*.md' 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "git ls-files failed with exit code ${LASTEXITCODE}: $($tracked -join [Environment]::NewLine)"
}

$missing = [System.Collections.Generic.List[string]]::new()
foreach ($markdown in $tracked) {
    $markdownPath = [string]$markdown
    if ([String]::IsNullOrWhiteSpace($markdownPath)) { continue }
    $absoluteMarkdown = Join-Path (Get-Location) $markdownPath
    if (-not (Test-Path -LiteralPath $absoluteMarkdown -PathType Leaf)) { continue }
    $content = [string](Get-Content -LiteralPath $absoluteMarkdown -Raw)
    $links = [regex]::Matches($content, '\[[^\]]*\]\(([^)]+)\)')
    foreach ($match in $links) {
        $target = $match.Groups[1].Value.Trim().Trim('<', '>')
        if ([String]::IsNullOrWhiteSpace($target) -or
            $target -match '^(?i:https?://|mailto:|#)') { continue }
        $targetPath = ($target -split '#', 2)[0]
        if ([String]::IsNullOrWhiteSpace($targetPath)) { continue }
        $resolved = [IO.Path]::GetFullPath((Join-Path (Split-Path $absoluteMarkdown -Parent) $targetPath))
        if (-not (Test-Path -LiteralPath $resolved)) {
            $missing.Add("$markdownPath -> $target")
        }
    }
}

if ($missing.Count -gt 0) {
    throw "Missing Markdown links:`n$($missing -join [Environment]::NewLine)"
}
Write-Output 'Markdown links verified.'
