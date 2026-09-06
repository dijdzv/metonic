param([ValidateSet('native', 'js', 'wasm-gc')][string]$Target = 'wasm-gc')
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$scratchRoot = Join-Path $repoRoot ('.work/typecheck-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratchRoot -Force | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

# Each fixture is a fresh module: no source mutation and no backend implementation in FE.
$cases = [ordered]@{
    'valid' = 'fn main { let b = @rpc.bind(@api.get_user(), fn(_input) { Ok(@api.User::{ name: "ok" }) }); let r : Result[@api.User, @api.GetUserError] = b.call(@api.GetUserInput::{ id: "1" }); println(r) }'
    'wrong-input' = 'fn main { let b = @rpc.bind(@api.get_user(), fn(_input) { Ok(@api.User::{ name: "ok" }) }); ignore(b.call(42)) }'
    'wrong-handler-output' = 'fn main { ignore(@rpc.bind(@api.get_user(), fn(_input) { Ok(42) })) }'
    'wrong-handler-error' = 'fn main { ignore(@rpc.bind(@api.get_user(), fn(_input) { Err(42) })) }'
    'wrong-client-output' = 'fn main { let b = @rpc.bind(@api.get_user(), fn(_input) { Ok(@api.User::{ name: "ok" }) }); let r : Result[Int, @api.GetUserError] = b.call(@api.GetUserInput::{ id: "1" }); println(r) }'
}
foreach ($entry in $cases.GetEnumerator()) {
    $caseRoot = Join-Path $scratchRoot $entry.Key
    New-Item -ItemType Directory -Path "$caseRoot/rpc", "$caseRoot/examples/p0/backend", "$caseRoot/probe" -Force | Out-Null
    Copy-Item -LiteralPath "$repoRoot/moon.mod.json" -Destination $caseRoot
    Copy-Item -LiteralPath "$repoRoot/rpc/core" -Destination "$caseRoot/rpc/core" -Recurse
    Copy-Item -LiteralPath "$repoRoot/examples/p0/backend/api" -Destination "$caseRoot/examples/p0/backend/api" -Recurse
    [IO.File]::WriteAllText("$caseRoot/probe/moon.pkg.json", '{"is-main":true,"import":[{"path":"local/p0/rpc/core","alias":"rpc"},{"path":"local/p0/examples/p0/backend/api","alias":"api"}]}', $utf8)
    [IO.File]::WriteAllText("$caseRoot/probe/main.mbt", $entry.Value, $utf8)
    # Windows PowerShell wraps stderr in NativeCommandError, even on successful commands.
    $ErrorActionPreference = 'Continue'
    & moon -C $caseRoot check --target $Target --deny-warn --output-json 1> "$caseRoot/stdout.log" 2> "$caseRoot/stderr.log"
    $code = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    $diagnostics = (Get-Content "$caseRoot/stdout.log", "$caseRoot/stderr.log" -Raw -ErrorAction SilentlyContinue) -join "`n"
    if ($entry.Key -eq 'valid') {
        if ($code -ne 0) { throw "Positive control failed: $diagnostics" }
        & moon -C $caseRoot build --target $Target --deny-warn
        if ($LASTEXITCODE -ne 0) { throw 'Isolated contract build failed' }
    } else {
        if ($code -eq 0) { throw "Invalid program accepted: $($entry.Key)" }
        if ($diagnostics -notmatch '(?i)type mismatch') { throw "Unexpected failure in $($entry.Key): $diagnostics" }
    }
    Write-Output "PASS $Target / $($entry.Key)"
}
Write-Output "Diagnostics: $scratchRoot"
