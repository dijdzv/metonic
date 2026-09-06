# Development guide

## Windows x64 setup

Install mise, PowerShell 7 (`pwsh`), and Visual Studio C++ x64 build tools with the Windows SDK.
From the repository root:

```powershell
mise trust
mise install
mise run bootstrap
mise run doctor
mise run hooks:install
mise run verify
mise run verify-native
```

`bootstrap` installs the exact compiler/core pair in `toolchain.json` with SHA256
verification. `doctor` rejects a different version. Tool binaries, caches, and
temporary diagnostics stay under ignored `.tools`, `_build`, and `.work` paths.

Run `mise run fmt` to format. For other MoonBit commands, use the project wrapper:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/moon.ps1 version --all
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/moon.ps1 check --target js
```

This explicit wrapper avoids falling back to an older global executable when
Windows PATH entries are ordered differently by a parent shell.

## Local pre-commit checks

`mise run hooks:install` uses mise's built-in Git hook generator. Run it once per
clone with the default Git hooks directory; it replaces `.git/hooks/pre-commit`,
so preserve any custom hook before running it. Git must be able to find `mise`
and PowerShell 7 on PATH.

`mise run pre-commit` can also run the checks manually. It checks staged changes
for whitespace errors. Staged Markdown changes trigger local link checks;
staged MoonBit source or package changes trigger `moon fmt --check`.
Formatting and link checks inspect the current working tree, including unstaged
edits. The hook never rewrites, stages, or stashes files, so partial staging is
preserved; it is not verification of an isolated staged snapshot. Full contract
tests remain in the verification tasks and PR CI.

## Toolchain updates

Check the current non-dev version on the official MoonBit distribution. Resolve
versioned compiler/core URLs, verify the compiler checksum against its published
SHA256, and record both archive hashes in `toolchain.json`. Update that pin in a PR,
run `bootstrap`, migrate source/configuration where necessary, then run both
verification tasks. CI must use the same committed pin.

Node 26.8.1 runs generated JavaScript; it is not a native product dependency.
pnpm 12.3.4 manages the pinned Playwright and PNG inspection tools used by browser
verification. Commit `pnpm-lock.yaml` and use `pnpm install --frozen-lockfile` in CI.
The native GPU probe uses Rust 1.98.1 from `rust-toolchain.toml` and exact wgpu
dependencies in `bridges/wgpu/Cargo.lock`. Install this toolchain through rustup;
the build uses `--locked` and does not change the global default toolchain.

## Native headless GPU probe

```powershell
rustup toolchain install 1.98.1 --profile minimal --component rustfmt
mise exec -- pnpm install --frozen-lockfile
mise run native:headless
$env:METONIC_GPU_FALLBACK = '1'
mise run native:headless
Remove-Item Env:METONIC_GPU_FALLBACK
```

This builds the MoonBit executable and Rust/wgpu DLL, then drives the executable
through JSON lines. MoonBit owns scene state; the DLL owns offscreen DX12
rendering and readback. PNG captures, adapter diagnostics, and results stay in
`.work/native-headless/default` or `fallback`. The verifier checks complete pixel
colors/bounds, stale requests, malformed input, capture failure, and shutdown.
It opens no window. Window input, IME, accessibility, MCP integration, and
production exclusion require separate verification. See the
[native verification record](verification/native-headless.md).

## Browser GPU probe

```powershell
mise install
mise exec -- pnpm install --frozen-lockfile
mise run browser:install
mise run browser:verify
mise run browser:headless
```

`browser:verify` builds release JS/WasmGC artifacts and compares their exported
state transitions in Node. `browser:headless` launches an isolated headless
Chromium and a loopback-only server, drives input, and checks the resulting GPU
pixels, resize, idle scheduling, and stop behavior. Screenshots and JSON results
are local files under ignored `.work/browser-headless`. Both processes close at
the end of verification. GPU unavailability is a failure, not a passed render test.
The default backend uses normal browser adapter selection. For software-GPU CI,
set `METONIC_GPU_BACKEND=swiftshader`; results identify the actual adapter and are
stored separately under `.work/browser-headless/<backend>`. The software mode is
an explicit test-browser configuration, not a fallback silently used in place of
a physical GPU result. `browser:server-test` checks the local server's asset boundary.

For direct inspection, `mise run browser:serve` serves the diagnostic harness at
`http://127.0.0.1:4173/`; choose `?target=js` or `?target=wasm-gc`. Only the explicit
distribution file list is served. These commands are prototype development tools,
not a production UI, semantic adapter, or MCP server.

## Native development control

Build with `mise run native:build` first. `mise run native:cli` reads one JSON
object per line and keeps a dedicated native process alive until stdin closes:

```json
{"op":"snapshot"}
{"op":"move","args":{"x":10,"y":20,"expected_revision":0}}
{"op":"activate","args":{"expected_revision":1}}
{"op":"capture","args":{"expected_revision":2}}
```

Capture returns response metadata and base64 PNG content. Each CLI or MCP launch
owns a fresh scene; it does not attach to an existing native window.

For an MCP host, use the pinned Node executable as the command and the absolute
path to `tools/devtools/native-mcp.mjs` as its single argument. Build and install
dependencies beforehand; do not send build-task output into MCP stdin/stdout.
The server exposes `native_snapshot`, `native_move`, `native_resize`,
`native_activate`, and `native_capture`. Errors use MCP error content. Unknown
arguments are rejected, and mutation/capture accepts `expected_revision`.

Run `mise run devtools:test`, `mise run native:control`, and
`mise run native:mcp-test` for transport and real-renderer checks. See the
[control verification record](verification/native-control.md) for scope and results.

## Repository layout

| Path | Purpose |
| --- | --- |
| `rpc/core` | Typed contract and in-process binding experiment |
| `examples/p0/backend/api` | Target-independent sample application contract |
| `examples/p0/backend/handlers` | Sample backend implementation |
| `examples/p0/frontend/app` | Contract-only frontend build probe |
| `scripts` | Bootstrap, formatting, and verification entry points |
| `docs/adr` | Architectural decisions and proposals |
| `docs/verification` | Reproducible experiments, evidence, and limitations |

`local/p0` is an unpublished experimental module identifier. It is not a public
package namespace or stable API commitment.

## Recording experiments

Keep a concise technical record: purpose, versions, commands, observed results,
unexecuted checks, and consequences. Prefer reproducible tests over a transcript
of terminal output. Raw logs belong in ignored local directories or CI artifacts.
Do not commit conversation transcripts, personal handoff notes, credentials, or
machine-specific absolute paths.

Test only the claims a change makes. Console execution is not GUI validation.
Internal semantic actions do not validate OS accessibility. Text insertion does
not validate Japanese IME composition. A runtime-disabled listener does not prove
that development tooling was excluded from a production binary.

## Work and release flow

- Use short-lived branches and small PRs. Squash merge after review and required checks.
- Main requires a PR, resolved review conversations, and `Windows verification`
  against the current base. Force pushes and deletion are prohibited, including for administrators.
- Use issues for task tracking with a purpose and completion criteria. Use `Closes #N`
  only for a completed task; use `Refs #N` for partial progress.
- Release from verified main commits with immutable `v0.x.y` tags. Add a maintenance
  branch only when supporting an older version in parallel becomes necessary.

## CI events and scope

| Event / change | Work performed |
| --- | --- |
| PR: documentation or license text only | Scope-classifier checks and local Markdown link validation |
| PR: source, toolchain, scripts, workflow, or any unrecognized path | The lightweight checks plus pinned bootstrap, native/JS/WasmGC, browser ABI/server, headless SwiftShader, and native software-DX12 verification |
| Manual dispatch | All checks, regardless of changed paths |
| Ordinary branch or main push | No duplicate verification run |

The required job always runs for PRs; only its expensive steps are conditional.
Unknown or empty change sets select full verification. Renames include both old
and new paths. A failing classifier or link check fails the job.
Headless verification images and JSON are retained as CI artifacts for seven days,
including failure images when available. Hosted software-GPU tests are distinct
from the local physical-GPU verification record.

There is no push-only task yet. Artifact packaging or publishing will use a
separate release-tag workflow when distribution exists, rather than rerunning
the PR test suite after every merge.

Development automation is specified in [ADR 023](adr/023-development-automation.md).
