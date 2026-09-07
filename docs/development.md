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

## Integrated window HTTP requests

For an interactive session, run `mise run demo`. It builds the browser host and
ordinary native release window, then runs both against the browser server's
HTTP endpoint. Closing native stops the owned server. Follow the
[integrated demo walkthrough](verification/integrated-demo.md) for controls and
current interaction differences. `demo:test` verifies launcher process ownership
and failure handling and is included in pre-commit.

The native window uses F7 to fetch user `1` through the standard HTTP/JSON
adapter. Set `METONIC_RPC_BASE` to the server origin (default
`http://127.0.0.1:4174`). The response or error appears below the editor without
replacing its text. Requests share the existing replace/cancel task scope;
F6 cancels the active task.

The development protocol accepts `load_user` with an optional `user_id`.
MCP exposes the same action as `window_load_user`; `window_snapshot` includes
`rpc_result` and `task_status`. Both operate on the ordinary window state.

Run `mise run native:window-rpc` for real HTTP success/domain-error checks
through the development protocol, or `mise run native:window-mcp` for the same
checks through the MCP SDK. Each verifier owns a loopback server and hidden
native window. These checks establish result state and preservation of editor
text. `native:window-rpc` also runs real-HTTP failure/recovery and pending-close
scenarios described in [UI HTTP failures](verification/ui-rpc-failures.md).

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
port 4173 and serves a fixed asset list with GET/HEAD and `no-store`.
POST `/rpc` uses the same bounded `rpc/http_host` handler as the standalone
RPC server. It exposes only the sample typed user lookup, not arbitrary handlers.
`browser:package` stages the selected WasmGC UI and a fixed-list ZIP separately
from the comparison assets. `browser:release-serve` serves it at `/release/`;
`demo` points users at that packaged page. The local server retains comparison
assets at `/`, but they are not shipped in the ZIP. See the
[package record](verification/browser-target.md) for deployment and exclusion scope.

The server reads each allowed file into memory before sending it and limits
concurrent connections to eight; it is a local development server, not a general
file host. WasmGC is the P0 default; verification still compares JS and WasmGC
independently. [The backend selection record](verification/browser-target.md)
documents artifact sizes and the production-packaging boundary.

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

For the current native build policy, debug hosts include development adapters;
the ordinary `window_app` release build excludes `handle`, `observation`, and
development request processing through package file selection. Release uses
empty hook implementations that do not reference development types or capture.
The UI loop, semantic state, input, rendering and HTTP client remain shared.
`window_dev` and `window_probe` are debug-only entry points under this policy;
optimized development hosts are not currently supported.

Run `mise run native:window-release-build` to build the production candidate.
`mise run native:release-lifecycle` builds it and an external MoonBit verifier,
then checks creation and orderly destruction of a visible window belonging to
the verifier's child PID. It never attaches to another process. This test opens
a window briefly. It does not establish rendered content, input or HTTP results.

`mise run native:accessibility` builds the same production window and verifies
shared editor text, external UIA Toggle/Value actions, resulting state, ordinary
editing after replacement and stale-provider rejection after close. A separate MoonBit supervisor owns both processes
so blocked UIA calls cannot leave the check waiting indefinitely. See
[native accessibility](verification/native-accessibility.md) for the pinned
dependency, small C ownership boundary and remaining text/selection requirements.

After both release and development builds,
`moon run scripts/verify-window-production-exclusion.mbtx` checks generated C
and link inputs with development code as a positive control. Both checks are
included in pre-commit. Real input/IME and full accessibility must still be verified
against this production candidate; initial UIA properties/actions do not prove them.

`native:window-build` builds the ordinary `window_app` executable.
`native:window` builds it and the dedicated `window_probe`, then runs the six
hidden verification scenarios against the probe. Only that probe reads
`METONIC_WINDOW_INIT_TEST` and owns synthetic input, staged assertions and
completion criteria. Both entry points share the UI event loop; lifecycle
callbacks let the probe observe initialization ownership without copying it.

`native:window-fixture-exclusion` checks generated C and MoonBit link inputs:
the ordinary executable excludes `window_probe`, while the probe is a positive
control. The same check runs after native builds in pre-commit. This establishes
fixture separation for the current debug build, not complete production exclusion
of control, observation and capture support or production accessibility.

`native_host/moon.work` isolates the external-loop adoption workspace while
importing the existing root renderer and integration fixture directly. The
ordinary window and async commands use the shared Windows event-loop adapter.
`native:async` uses structured MoonBit jobs; `native:window` handles input,
resize and GPU initialization through the prepared window dependency.

The window also renders the shared semantic editor using `text_raster` and the
pinned Noto Sans JP asset. Its build prepares and verifies that asset directly.
Committed text replaces the selection; Backspace deletes the selection or one
Unicode scalar. Selection highlights and staged composition use the shared text
layout; grapheme navigation and physical IME verification remain incomplete.
Left/right move the insertion position when text is focused; Tab switches text
and scene focus. Up/down and Enter/Space control the rectangle only with scene
focus and no active composition. Scene Space and Backspace do not edit text.
F5 starts a delayed move to the left; F6 cancels it. A new F5 replaces the pending
job. The ordinary window uses the shared task-scope model to reject obsolete
results and joins canceled work before releasing GPU/window resources.

The hidden window verification injects character messages, replaces Japanese
text, inserts and deletes a supplementary character, and checks caret state.
It renders through the same pass into an offscreen texture to check glyph
presence and clearing down to the insertion caret after an empty update. This is
not a swap-chain screenshot or a test of physical input, glyph-shape accuracy,
IME or OS accessibility. Capture normalizes channel order to RGBA while retaining
the surface's encoded color values.

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
window, async or surface modes. Window and async build the dedicated native host workspace;
the other product modes also build the MoonBit headless executable. Window,
async and surface rendering use the published MoonBit binding. The surface
diagnostic and binding comparison retain the C HWND fixture; window and async
use the prepared window dependency and a context-free C wake thunk. The script
checks output artifacts and rejects unsupported modes before building.
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
distribution file list and sample `/rpc` endpoint are served. These commands are prototype development tools,
not a production UI, semantic adapter, or MCP server.

Use **Load user** to request user `1`, or another ID to observe the domain error.
The browser input adapter sends committed text and UTF-16 selection to the same
MoonBit semantic model used by the native window. GPU text reads that state;
HTTP completion and resize do not import editor contents from the DOM.
Composition updates use the shared preview model without mutating committed text.
On composition end the adapter accepts the browser's final value and selection,
including cancellation, rather than interpreting empty composition data as deletion.
Reset replaces the editor and stop disposes it.

The headless editor flow checks synthetic composition over a supplementary
character, HTTP completion, resize, reset and events after stop on JS and WasmGC.
It does not establish physical IME candidate placement or browser/IME-specific
composition event ordering. Those still require the browser IME evaluation.

The MoonBit JSON contract encodes and decodes requests on both JS and WasmGC;
fetch owns browser HTTP I/O and abort signals. Responses update the shared task
scope and append result text to the GPU text layer without replacing the editor.
Cancel, replacement and reset abort the pending request. The browser transport
bounds responses to 64 KiB and uses a three-second timeout.

`browser:headless` checks real same-origin success and domain errors, editor
preservation, and cancellation/replacement with an intercepted pending request
on both targets. MoonBit tests separately deliver late responses after task
replacement, cancellation and disposal. The packaged-UI scenario additionally
uses real loopback HTTP for timeout, disconnect, size/depth/content failures,
recovery, cancellation/replacement and stop with a pending request. See
[UI HTTP failures](verification/ui-rpc-failures.md) for the fixture boundary.
These checks do not establish physical IME or accessibility parity.

`mise run browser:async` checks delayed completion while input remains responsive,
superseded results, cancellation, failure, reset, and stop on both JS and WasmGC.
The same harness includes Move after delay, Fail, and Cancel controls. See the
[async verification record](verification/browser-async.md) for the boundary between
this timer experiment and a general asynchronous runtime.

## Native development control

### Integrated window

The native editor supports Ctrl+A (select all), Home/End (start/end of the
document), text click (place the insertion position), and Shift+click (select
from the preserved anchor). Left/right move over Unicode scalar boundaries;
Shift extends or reverses selection around that anchor. Typing replaces the
selected range; Backspace deletes the selection or preceding Unicode scalar.
Tab switches text/scene focus, and clicking the scene restores its keyboard
controls. Up/down still move the rectangle. Selection, a steady insertion caret,
pointer placement and IME positioning use the same saved text layout. Drag
selection, grapheme/visual-bidi and vertical navigation remain unfinished.

Development snapshots include `selection_anchor` and `caret` in addition to the
ordered range, so selection direction can be observed without reconstructing it
from previous requests.

CLI `select` and MCP `window_select` accept `selection_start`, `selection_end`
and optional `expected_semantic_revision`. Offsets are UTF-16 boundaries; splitting
a surrogate pair is rejected. Selection is applied on the UI event path before
its response is returned, like editing.

`native:window-mcp` verifies selection/replacement and the appearance/removal of
selection-colored pixels through the shared offscreen pass. `native:window`
checks Home/End, pointer placement and control-character filtering using messages
posted to the application's own HWND. These are not physical-input or real-IME
checks; Ctrl+A and Shift+click still require direct input verification.

`mise run native:window-dev-build` builds the dedicated `window_dev` entry point
under `.work/native-host-build/native/debug/build/local/native_host/window_dev/`.
Launch `window_dev.exe` from the repository root with stdin/stdout pipes to control
the same window implementation as `native:window`. Set `METONIC_DEV_HIDDEN=1` for
hidden operation. EOF closes the owned window. This is a launch-scoped connection;
it does not attach to an independently running application.

Send one JSON object per line, with positive, strictly increasing `id` values:

```json
{"id":1,"op":"snapshot"}
{"id":2,"op":"insert","text":"日本語","expected_semantic_revision":1}
{"id":3,"op":"backspace","expected_semantic_revision":2}
{"id":4,"op":"start_update"}
{"id":5,"op":"cancel_update"}
```

Replies include the request ID, an error string (empty on success), text and
selection state, semantic revision, submitted frame count and task status.
Edits check the optional expected revision on the UI event path immediately
before applying the change. Lines are limited to 4095 bytes; malformed/oversized
requests and duplicate IDs do not prevent subsequent valid requests.

`mise run native:window-control` verifies editing, stale-revision rejection,
request correlation, malformed/oversized input recovery and EOF cleanup on
default and fallback GPU adapters. It is part of the local pre-commit gate.
These hidden checks do not establish physical input or OS accessibility.
For MCP, use the pinned Node executable with the absolute path to
`tools/devtools/window-mcp.mjs`. This dedicated server exposes `window_snapshot`,
`window_insert`, `window_backspace`, `window_start_update` and `window_cancel_update`.
`window_capture` returns a PNG image plus pixel dimensions, the submitted frame
number and `source: shared_offscreen_pass`. It reuses the current window's render
pass; it is not a desktop or swap-chain screenshot. PNG encoding runs in MoonBit.
It owns the launched window and uses the same JSON control path. Set
`METONIC_DEV_HIDDEN=1` in the MCP launch environment for hidden operation.
`mise run native:window-mcp` verifies the SDK connection, edits, stale revision
rejection and cancellation; its assertions run in MoonBit. Request abort or timeout
closes the owned session rather than promising rollback of an already applied edit.
The older `native_*` MCP commands below still use the separate headless renderer.
Protocol imports are in `window_dev`; release package file selection excludes
development handlers and capture support. The generated-code/link-input checks
and remaining production behavior verification are described under Native host
workspace above.

### Existing headless renderer control

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
