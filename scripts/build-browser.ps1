[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repoRoot
try {
    . (Join-Path $repoRoot 'scripts/activate-toolchain.ps1')

    & moon build examples/p0/browser --target js --release --deny-warn
    if ($LASTEXITCODE -ne 0) { throw "moon JS build failed with exit code $LASTEXITCODE" }

    & moon build examples/p0/browser --target wasm-gc --release --deny-warn
    if ($LASTEXITCODE -ne 0) { throw "moon WasmGC build failed with exit code $LASTEXITCODE" }

    $jsArtifact = Join-Path $repoRoot '_build/js/release/build/examples/p0/browser/browser.js'
    $wasmArtifact = Join-Path $repoRoot '_build/wasm-gc/release/build/examples/p0/browser/browser.wasm'
    if (-not (Test-Path -LiteralPath $jsArtifact -PathType Leaf)) { throw "Missing JS artifact: $jsArtifact" }
    if (-not (Test-Path -LiteralPath $wasmArtifact -PathType Leaf)) { throw "Missing WasmGC artifact: $wasmArtifact" }

    $dist = Join-Path $repoRoot '.work/browser-dist'
    New-Item -ItemType Directory -Force -Path $dist | Out-Null
    $hostRoot = Join-Path $repoRoot 'examples/p0/browser/host'
    foreach ($name in @('index.html', 'style.css', 'host.mjs', 'loader.mjs')) {
        $source = Join-Path $hostRoot $name
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing browser host file: $source" }
        if ($name.EndsWith('.mjs')) {
            & node --check $source
            if ($LASTEXITCODE -ne 0) { throw "Node syntax check failed for $source with exit code $LASTEXITCODE" }
        }
        Copy-Item -LiteralPath $source -Destination (Join-Path $dist $name) -Force
    }
    Copy-Item -LiteralPath $jsArtifact -Destination (Join-Path $dist 'app.mjs') -Force
    Copy-Item -LiteralPath $wasmArtifact -Destination (Join-Path $dist 'app.wasm') -Force
}
finally {
    Pop-Location
}
