# Development guide

## Work tracking

Use Issues for current status, intermediate investigation results, blockers and
next steps. Update them when meaningful evidence or a linked PR changes the state
of the work. Distinguish local experiments from merged behavior and keep acceptance
criteria open until their full scope is verified. Keep design decisions in ADRs
and reproducible verification records in docs; do not use them as running task logs.

Before starting a new workstream, create or identify its Issue with scope,
acceptance criteria, priority and dependencies. Track requested migrations and
deferred investigations explicitly; do not leave them only in prose documents.
An explicit user priority takes precedence over opportunistic feature work.
Record priority changes and their reasons in the tracking Issue. At meaningful
validation results and PR integration, update the affected Issues with evidence,
remaining work and the next action. Use comments for intermediate results and
edit the body for the current scope or acceptance criteria.

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

## MoonBit scripts

Development scripts, verification and CLI logic use MoonBit by default. Standalone
tools use `.mbtx`; `scripts/doctor.mbtx` is the first migrated tool and runs through
`mise run doctor`. It pins `moonbitlang/async@0.21.2` (Apache-2.0) for file/process
access. Bootstrap refreshes the registry index so a fresh installation can resolve
that fixed version. Use the project-pinned executable rather than an older global
`moon` installation.

The remaining PowerShell and MJS scripts are migration work, not an adopted
long-term scripting stack. Compiler acquisition and MSVC environment activation
still use the Windows bootstrap boundary. Browser WebGPU/Playwright and external
MCP SDK calls require small host adapters; orchestration and assertions should
move to MoonBit where supported. Wrapping an unchanged script does not constitute
a completed migration.

`mise run browser:build` now uses `scripts/build-browser.mbtx` for compilation,
asset verification and staging. It copies the pinned Noto Sans JP font and its
OFL license into the ignored browser distribution. The browser checks the font
hash again before passing bytes to MoonBit. DOM, WebGPU and Playwright calls
remain in their host adapters.

`browser:build` also builds the MoonBit development HTTP server in
`tools/browser_server` for the Wasm runtime. `browser:serve` and browser verifiers
launch that artifact directly through the pinned `moonrun`. It binds loopback
port 4173 and serves only a fixed asset list with GET/HEAD and `no-store`.
The server reads each allowed file into memory before sending it and limits
concurrent connections to eight; it is a local development server, not a general
file host. Browser UI execution still compares JS and WasmGC independently.

`browser:server-test` uses `scripts/verify-browser-server.mbtx` to launch the
server and verify asset MIME types, cache policy, GET/HEAD, method rejection and
the path allowlist. It bounds readiness and the complete run separately and
cancels the child process when verification finishes or fails.

## Local pre-commit checks

Tracked Markdown links are checked by `moon run scripts/verify-docs.mbtx`.
The check resolves relative file targets and ignores external URLs and fragments;
it does not validate heading anchors or implement a complete Markdown parser.

Contract compile-failure checks use `scripts/verify-types.mbtx`. Set
`METONIC_VERIFY_TARGET` to `js`, `wasm-gc` (default), or `native`; native builds
require the MSVC environment. Each case copies only the tracked RPC core and API
contract into a fresh module under `.work`. The positive control must check and
build; negative cases must report a type mismatch. Diagnostics remain in each
case's `probe/check.stdout` and `probe/check.stderr` files.

`mise run verify` and `mise run verify-native` use `scripts/verify.mbtx` for
toolchain checks, formatting checks, tests, the contract-only frontend and
compile-failure fixtures. Native mode obtains the MSVC environment through
Microsoft's `vswhere` and `VsDevCmd.bat`; a temporary batch file captures that
environment for child processes. Validation logic runs in MoonBit, and the
parent shell's environment is not modified. Toolchain installation remains a
separate bootstrap step.

Native probe build tasks use `scripts/build-native.mbtx` with explicit headless,
window or async modes. Each mode builds the locked Rust bridge and headless
baseline; window/async additionally rebuild their C stub and executable. The
script checks output artifacts and rejects unsupported modes before building.
This migrates build orchestration, not the retained Rust/C implementation.

`mise run hooks:install` uses mise's built-in Git hook generator. Run it once per
clone with the default Git hooks directory; it replaces `.git/hooks/pre-commit`,
so preserve any custom hook before running it. Git must be able to find `mise`
and PowerShell 7 on PATH.

The pinned formatter does not directly accept `.mbtx`. The local hook runs
`scripts/format-scripts.mbtx`, which formats tracked scripts' import blocks as
`moon.pkg` and their bodies as `.mbt` using the same pinned `moonfmt`. It writes
back only after all formatter invocations succeed and rejects unsupported
frontmatter instead of silently skipping it.

`mise run pre-commit` runs the same local gate manually. The MoonBit `.mbtx`
orchestrator rejects tracked unstaged edits, checks staged whitespace, runs
MoonBit/Rust formatters and stops if formatting changes files. Review and stage
those changes before retrying; the hook never stages or stashes them for you.
It then runs MoonBit static checks, the native/JS/WasmGC contract tests, browser
artifact/server/GPU/async checks, and native GPU/control/MCP/semantics/window/async
tests, including the existing-binding comparison. Markdown links are also checked.
Dependencies and headless Chromium must already be installed.

All of these checks are required before a commit and push. The existing PS/MJS
test implementations remain temporarily behind the MoonBit orchestration; this
does not count as migrating their implementation. Untracked experiments are not
validated by this gate until explicitly integrated into its checks.

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

`browser:verify` builds release JS/WasmGC artifacts and a MoonBit JS verifier.
The Node entry point only loads both artifacts and invokes the verifier;
MoonBit checks export availability, state transitions, return values and agreement
between targets. `browser:headless` launches an isolated headless
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

`mise run browser:async` checks delayed completion while input remains responsive,
superseded results, cancellation, failure, reset, and stop on both JS and WasmGC.
The same harness includes Move after delay, Fail, and Cancel controls. See the
[async verification record](verification/browser-async.md) for the boundary between
this timer experiment and a general asynchronous runtime.

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

The CLI runs as a MoonBit Wasm host program. For machine consumption, build it
first and launch `.tools/moonbit/bin/moonrun.exe` with the absolute path to
`_build/wasm/release/build/tools/native_cli/native_cli.wasm` and `--root` followed
by the absolute repository path. This keeps build output out of the JSON stream.
Input lines are limited to 4095 bytes and decoded as strict UTF-8. An invalid or
oversized line produces an error response; subsequent valid lines remain usable.

Build `mise run native:session-build` before using MCP. For an MCP host, use the pinned Node executable as the command and the absolute
path to `tools/devtools/native-mcp.mjs` as its single argument. Build and install
dependencies beforehand; do not send build-task output into MCP stdin/stdout.
The server exposes `native_snapshot`, `native_move`, `native_resize`,
`native_activate`, and `native_capture`. Errors use MCP error content. Unknown
arguments are rejected, and mutation/capture accepts `expected_revision`.

Run `mise run devtools:test`, `mise run native:control`,
`mise run native:cli-test`, `mise run native:session-test`, and `mise run native:mcp-test` for transport and
real-renderer checks. See the
[control verification record](verification/native-control.md) for scope and results.

`mise run native:client-test` checks the MoonBit process client used by migrated
verification tools. `mise run native:semantics` builds its MoonBit verifier for
the Wasm host runtime before running it against the native renderer. The verifier
checks semantic actions, UTF-16 selection boundaries, stale references and full
capture pixels. Node hosts the official MCP SDK; `tools/native_session` owns the
renderer, temporary capture file and PNG encoding through the MoonBit client.
`native:client-test` builds the MoonBit control fixture before exercising response
correlation, delays, malformed replies and process failures. Direct `moon test`
invocations for that package require `mise run native:fixture-build` first.
`native:session-test` checks state, complete capture pixels, stale revisions and
temporary-directory cleanup after EOF. The Node session tests cover Promise and
AbortSignal behavior at the SDK boundary. See the
[semantic verification record](verification/semantics.md) for measured scope.

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
- Main requires a PR and resolved review conversations. Force pushes and deletion
  are prohibited, including for administrators. Automated PR status checks are
  not required during this initial local-verification phase.
- Use issues for task tracking with a purpose and completion criteria. Use `Closes #N`
  only for a completed task; use `Refs #N` for partial progress.
- Release from verified main commits with immutable `v0.x.y` tags. Add a maintenance
  branch only when supporting an older version in parallel becomes necessary.

## CI events and scope

| Event / change | Work performed |
| --- | --- |
| Pull request | No automatic duplicate verification |
| Manual dispatch | All checks, regardless of changed paths |
| Ordinary branch or main push | No duplicate verification run |

Local pre-commit is the normal verification gate. Manual dispatch is available
for explicit hosted-environment diagnosis, not a requirement for every PR.
Headless verification images and JSON are retained as CI artifacts for seven days,
including failure images when available. Hosted software-GPU tests are distinct
from the local physical-GPU verification record.

There is no push-only task yet. Artifact packaging or publishing will use a
separate release-tag workflow when distribution exists, rather than rerunning
the PR test suite after every merge.

Development automation is specified in [ADR 023](adr/023-development-automation.md).
