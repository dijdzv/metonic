# Development guide

## Work tracking

Use one executable outcome per Issue. Split independently deliverable changes or
investigations before starting them; put task-specific evidence and acceptance
criteria on the smaller Issue. A broad historical Issue is not a work queue.

Each active task has exactly one priority label: `priority:p0` for urgent blockers,
`priority:p1` for the current work, `priority:p2` for subsequent work, or
`priority:p3` for optional/deferred work. These labels are independent of the P0
product milestone. Do not maintain a separate priority-order Issue or duplicate
the order in prose. Use labels to select priority and GitHub blocked-by/blocking
relationships for actual prerequisites. Related work alone is not a dependency;
use a link for context. Parent/sub-issue relationships describe decomposition,
not execution order.

The Issue body is the current task summary: outcome, acceptance criteria, present
state, unresolved questions and links to evidence. Edit it when those facts
change, distinguishing local verification from merged behavior. Close the task
only when its acceptance criteria hold; use the linked PR for implementation and
merge details.

Add a comment only for an unresolved discussion, a decision needing a response,
or unique evidence whose chronology matters. Incorporate resolved conclusions
into the body. Do not post routine start/progress/merge reports, repeated test
summaries, clean-worktree reports, or the same update on several linked Issues.
Link to tests, commits, PRs and verification records instead of copying them.
Preserve historical comments with unique evidence or incoming links; comment
count alone is not a reason to delete history. Retire obsolete trackers with
links to their replacement tasks, without marking unfinished work completed.

Keep durable design decisions in ADRs and reproducible verification in docs.
Issue-local notes belong on the task that needs them, not in public handoff logs.

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

Run `mise run fmt` to format. For other MoonBit commands, use the pinned executable
inside the mise environment:

```powershell
mise exec -- ./.tools/moonbit/bin/moon.exe version --all
mise exec -- ./.tools/moonbit/bin/moon.exe check --target js
```

The explicit path avoids falling back to an older global executable. mise supplies
MOON_HOME, PATH and the pinned wgpu library environment from `mise.toml`; a separate
PowerShell activation or command wrapper is unnecessary. Bootstrap remains a
PowerShell installation boundary because MoonBit is not yet available on a fresh
checkout.

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

`browser:async` and `browser:headless` use `tools/browser_supervisor` to own the
server and Node verifier processes. Run these mise tasks rather than invoking
their JavaScript adapters directly. Playwright browser creation and normal
`browser.close()` remain in the JavaScript boundary. Process diagnostics are
written under `.work/browser-supervisor/<mode>/<backend>`, separate from browser
screenshots and assertion results. `browser:supervisor-test` builds the dedicated
process fixture before testing the supervisor; it is included in pre-commit.
See [process ownership and limits](verification/browser-supervisor.md) for its
failure contract and reproduction commands.

## Native host workspace

`native_host/moon.work` isolates the external-loop adoption workspace while
importing the existing root renderer and integration fixture directly. The
ordinary native window command remains on its existing C boundary.
`native:async` uses the shared adapter and structured MoonBit jobs after comparison
with the old C worker scenario. Full host adoption remains tracked in
[Issue 77](https://github.com/dijdzv/metonic/issues/77).

`mise run native:host-build` prepares pinned source archives, applies the reviewed
window and async patches, and builds the existing GPU integration fixture. The
preparation tool uses `.work/native-deps/cache` for archives and
`.work/native-deps/sources` for verified patched sources. To prepare using only
cached archives, run:

```powershell
mise exec -- ./.tools/moonbit/bin/moon.exe run scripts/prepare-native-deps.mbtx -- --offline
```

Archive SHA256 values are fixed in the preparation tool. Source-tree comparison
rejects edits to prepared dependencies; make deliberate changes to the tracked
patches rather than editing the generated source tree. A source mismatch is an
error, not permission to overwrite that tree. A failed or interrupted preparation
may leave diagnostic files under `.work`; inspect those before removing them.

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
window, async or surface modes. Async builds the dedicated native host workspace;
the other product modes also build the MoonBit headless executable. Window,
async and surface rendering use the published MoonBit binding. The window and
surface probes retain the C HWND stub; async uses the prepared window dependency
and a context-free C wake thunk. The
script checks output artifacts and rejects unsupported modes before building.
Headless rendering also uses the binding. The shared Win32 C boundary remains
under comparison; application-owned GPU composition is MoonBit.

`native:surface` builds a separate MoonBit surface renderer probe using the
existing HWND boundary and the published wgpu binding, without building the Rust
DLL. Its [device replacement diagnostic](verification/surface-device-replacement.md)
compares reuse and recreation of the surface. The raw diagnostic does not exercise
the renderer class or the normal window/worker input verification.

The opt-in [Windows event-pump evaluation](verification/windows-event-pump.md)
records the candidate window library's wakeup and pumping behavior. It does not
replace the normal window/worker verification gate.

Bootstrap, verification, pre-commit and native builds run
`scripts/prepare-wgpu.mbtx` before using the root module's wgpu binding.
It downloads the pinned Windows x64 MSVC
wgpu-native archive through `gh`, verifies SHA256 with `certutil`, and extracts
it with `tar` under `.work/wgpu-assets`. These tools must be available on PATH.
mise and the toolchain wrapper set `MBT_WGPU_NATIVE_ROOT` and
`MBT_WGPU_LINK_MODE=static`; the build and verification scripts also configure
their child processes. The upstream module hook runs for non-native builds too,
so these settings apply to all root-module targets. The preparation creates an ignored CommonJS package
boundary under `.mooncakes` for the upstream prebuild hook; the repository root
remains ESM for generated browser verification modules. It does not patch the
dependency's source files.

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
MoonBit formatters and stops if formatting changes files. Review and stage
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
pnpm 12.3.4 manages the pinned Playwright and MCP SDK development tools.
Commit `pnpm-lock.yaml` and use `pnpm install --frozen-lockfile` in CI.
Native probes use the pinned prebuilt wgpu-native library through the MoonBit
binding and require the Visual Studio C++ build tools. Building the project does
not require a Rust toolchain; the upstream GPU implementation still contains Rust.

## Native headless GPU probe

```powershell
mise exec -- pnpm install --frozen-lockfile
mise run native:headless
$env:METONIC_GPU_FALLBACK = '1'
mise run native:headless
Remove-Item Env:METONIC_GPU_FALLBACK
```

This builds the MoonBit executable with statically linked wgpu-native, then drives
it through JSON lines. MoonBit owns scene state and persistent GPU composition
through `Milky2018/wgpu_mbt`; this task does not build the custom Rust DLL.
PNG captures, adapter diagnostics, and results stay in
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

Reuse the configured build directory for repeated runs of the same experiment.
Create a separate output directory only when a comparison needs isolation.
After preserving results and reproduction instructions, remove obsolete generated
build outputs. Keep logs separate from binaries so cleanup does not erase evidence;
do not treat patched source checkouts or verified offline dependency archives as
disposable build output.

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
