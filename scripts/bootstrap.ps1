param([string]$InstallDirectory = '.tools/moonbit')
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$repoRoot = Split-Path $PSScriptRoot -Parent
$lock = Get-Content "$repoRoot/toolchain.json" -Raw | ConvertFrom-Json
if ($env:OS -ne 'Windows_NT' -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
    throw 'The pinned bootstrap currently supports Windows x64 only.'
}
$toolsRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.tools'))
$installRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot $InstallDirectory))
if (!$installRoot.StartsWith($toolsRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'InstallDirectory must be a child of this repository .tools directory.'
}
$marker = Join-Path $installRoot 'metonic-toolchain.json'
if (Test-Path -LiteralPath $marker) {
    $installed = Get-Content $marker -Raw | ConvertFrom-Json
    if ($installed.archiveSha256 -eq $lock.archiveSha256 -and $installed.coreSha256 -eq $lock.coreSha256) {
        Write-Output "Toolchain already installed: $installRoot"
        exit 0
    }
}
$stage = Join-Path $toolsRoot ('stage-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage -Force | Out-Null
foreach ($asset in @(
    @{ Url = $lock.archiveUrl; Hash = $lock.archiveSha256; File = 'compiler.zip' },
    @{ Url = $lock.coreUrl; Hash = $lock.coreSha256; File = 'core.zip' }
)) {
    $archive = Join-Path $stage $asset.File
    Invoke-WebRequest -Uri $asset.Url -OutFile $archive
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $asset.Hash) {
        throw "Checksum mismatch: $($asset.Url)"
    }
}
$payload = Join-Path $stage 'payload'
Expand-Archive -LiteralPath "$stage/compiler.zip" -DestinationPath $payload
Expand-Archive -LiteralPath "$stage/core.zip" -DestinationPath "$payload/lib"
$env:MOON_HOME = $payload
$env:PATH = "$payload/bin;$env:PATH"
& "$payload/bin/moon.exe" -C "$payload/lib/core" bundle --warn-list -a --all
if ($LASTEXITCODE -ne 0) { throw 'Standard library bundle failed' }
$version = (& "$payload/bin/moon.exe" version --all | Out-String)
if ($LASTEXITCODE -ne 0 -or !$version.Contains($lock.compiler) -or !$version.Contains($lock.moon)) {
    throw "Unexpected toolchain version: $version"
}
Copy-Item -LiteralPath "$repoRoot/toolchain.json" -Destination "$payload/metonic-toolchain.json"
# Keep the prior toolchain for rollback; both resolved paths are within .tools.
if (Test-Path -LiteralPath $installRoot) {
    $backup = Join-Path $toolsRoot ('previous-' + [guid]::NewGuid().ToString('N'))
    Move-Item -LiteralPath $installRoot -Destination $backup
}
Move-Item -LiteralPath $payload -Destination $installRoot
Write-Output "Installed $($lock.compiler): $installRoot"
