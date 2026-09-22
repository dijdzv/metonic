# Library reuse evaluation

Initial evaluation: 2026-09-06; current boundaries reconciled on 2026-09-23.
This supplements dependency selection; it does not replace the
architecture or authorize adoption of every candidate. Working implementations
remain comparison baselines until equivalent requirements pass.

## Current boundaries

| Existing code | Responsibility | Reuse comparison |
| --- | --- | --- |
| `native_gpu/surface_renderer.mbt` | Shared HWND presentation and GPU resource lifetime | Adopted `Milky2018/wgpu_mbt`; custom Rust renderer removed |
| `native_host/accessibility` | Production Windows accessibility | Official AccessKit C 0.22.3; MoonBit state/tree translation and a bounded C request mailbox; [scope and remaining work](native-accessibility.md) |
| `tools/native_surface_probe/window.c` | Isolated device-replacement diagnostic HWND | Ordinary window migrated to `wzzc-dev/window/windows`; diagnostic retained for comparison |
| `native_host/async_app`, `native_host/windows_loop` | Async jobs, cancellation, completion delivery and UI wakeup | Adopted `moonbitlang/async` structured tasks and external-loop API with the prepared window library; custom C workers replaced after [comparison](native-async.md); context-free C wake thunk retained |
| `native_gpu`, `examples/p0/native_headless` | Persistent offscreen GPU resources, readback and capture | Adopted `Milky2018/wgpu_mbt@0.16.0`; headless C stub removed, stdio and file writing use MoonBit async |
| `core/layout` | Fixed-height vertical rows, linear fixed/fill placement, pixel scrolling, visible intersections, hit testing and focus reveal | Adopted `Milky2018/chicle@0.6.1` behind `VerticalList` and `layout_linear`; this scoped API is not a general layout engine or virtualized list; see [ADR 034](../adr/034-shared-list-layout.md) |
| `browser_host/app/input*.mbt` | Text-input listeners, DOM values, selection, composition, focus and scroll observation | Adopted generated WebSys bindings for JS/WasmGC through the pinned `local/websys-input` module; [input](browser-input.md) records generation, lifetime tests and bounded actual-IME acceptance |
| Other `browser_host/app` operations | Scene/text GPU resources and frame submission, control placement, HTTP, timers and bounded font download | Generated WebSys bindings for JS/WasmGC; [HTTP](browser-http.md), [font transfer](browser-font-transfer.md) and [text GPU](browser-text-gpu.md) records describe the boundaries |
| `examples/p0/browser/host/*.mjs` | Browser startup, adapter/device acquisition, canvas coordination, animation-frame scheduling, module loading and buffer transfer | Remaining JavaScript adapter; GPU drawing, text-input ownership, control placement and font hash validation have moved to MoonBit |
| `tools/devtools/*.mjs`, `scripts/*` | CLI/MCP transport and development verification | MoonBit orchestration first; external SDK adapters scoped separately |
| `core/text_position`, `core/task_scope`, `core/semantics` | Position validity, task lifetime and semantic actions | Framework packages without sample dependencies; P0 initialization and legacy actions remain in its semantic adapter |
| `platform/windows/ime_presentation` | Interpretation of Windows IMM composition attributes | Pure Windows presentation policy; separate from platform-independent text offsets |

`examples/p0` contains bounded architecture probes, not a supported public API.
Shared prototype packages currently live there so each experiment can reuse the
same contracts. Promote reusable implementations to library packages when their
responsibility and tests are established; keep demonstration hosts in examples.
Dependency experiments use isolated modules under `experiments` during comparison.
The Windows candidate now has a locally evaluated bounded-pump correction and
positive/negative contract comparison; see [event-pump results](windows-event-pump.md).
The [GPU external-loop comparison](windows-gpu-external-loop.md) reuses the
unchanged renderer in an isolated workspace. The async scenario now uses the
shared host. The ordinary native window also uses the prepared window library
and shared external-loop adapter; its former custom C host and application
workers have been replaced. The retained wake thunk and accessibility mailbox
are external-thread boundaries, not an unfinished host migration. See
[ADR 030](../adr/030-native-external-event-loop.md) and
[production accessibility](native-accessibility.md).
The initial checkout checks below remain historical results, not adoption claims.
The font-backed browser integration now uses a root `text_raster` package and pins
moon_cosmic in the root module. Demonstration hosts remain under `examples/p0`.

## Remaining project-owned foreign-language files

The tracked-source inventory on 2026-09-20 contains 10 C and 20 `.mjs` files,
with no tracked PowerShell or Rust source. This excludes downloaded dependencies,
generated bindings/build output, and ignored local experiments. It does not imply
that every line in the remaining adapters is irreducible.

| Files | Current boundary and status |
| --- | --- |
| `native_host/windows_loop/wake.c`, `experiments/window_async_contract/wake.c` | Context-free callbacks from foreign threads into the window wake mechanism; application task policy is MoonBit |
| `native_host/accessibility/mailbox.c` | AccessKit callbacks and bounded native request ownership; semantic state and action handling are MoonBit |
| `native_host/accessibility_probe/navigate.c` | Windows UIA/COM client and owned-window input observation used by verification, not the production editor |
| `native_host/mailbox_probe/boundary.c`, `native_host/sdk_mailbox_probe/boundary.c` | Native-thread/SDK callback ownership and lifetime verification |
| `experiments/async_waiter_handles/host.c` | Windows handle-count observation and a native callback for the async regression |
| `experiments/wgpu_binding/window_bridge.c`, `tools/native_surface_probe/window.c`, `tools/native_surface_probe/bridge.c` | Diagnostic HWND/handle boundaries for binding and device-replacement comparisons; not the ordinary application's window implementation |
| Seven `examples/p0/browser/host/*.mjs` files | Development/release loader and environment adapters, browser startup/presentation coordination and buffer transfer |
| Five `scripts/*.mjs` files | Browser/Node API endpoints for artifact, headless, async and MCP verification; their MoonBit verifier packages own the corresponding protocol/pixel assertions |
| Eight `tools/devtools/*.mjs` files | Node subprocess/stream and MCP SDK adapters, browser observation and their API-boundary tests; shared session framing/admission policy is imported from generated MoonBit |

The [surface-reuse investigation](https://github.com/dijdzv/metonic/issues/58)
and [window upstream proposals](https://github.com/dijdzv/metonic/issues/88)
own further diagnostic/native-boundary evaluation. The font loader now uses WebSys
WebCrypto and owned buffer conversions; earlier browser-binding patch proposals
are not application dependencies. A retained comparison
fixture is not evidence that its implementation is required in the application.
WGSL shader text and HTML/CSS remain GPU/web formats, distinct from orchestration
scripts. The generated Visual Studio environment `.cmd` bridge invokes the vendor
build environment; it is not a PowerShell setup dependency.

Browser scene hit testing, arrow-step movement and Space/Enter activation are
implemented in MoonBit. The JavaScript host forwards canvas-relative pointer
coordinates and key names, preserves focus and prevents default behavior for
recognized keys, including clamped movement. MoonBit tests cover hit edges and
ignored keys; the artifact verifier compares generated JS/WasmGC input results.

## Initial results

These are source-checkout results unless explicitly identified as published
package tests. Checkout version fields do not prove registry equivalence.

| Area | Implementation at initial evaluation | Candidate/version | Required behavior | Native result | Browser result | Gap and decision | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| GPU | MoonBit offscreen and surface renderers | Published `Milky2018/wgpu_mbt@0.16.0` | DX12, pixels, surface lifetime | Headless readback, hidden HWND input and worker completion passed on both local adapters | Not a browser binding | Adopted for native rendering; Win32 and worker C boundaries remain | [GPU evaluation](wgpu-mbt.md), [worker verification](native-async.md) |
| Window | Direct Win32 C host | `wzzc-dev/window` checkout version `0.5.4-0.1.7` | Hidden HWND, events, resize, wakeup and cleanup | `moon check --target native` passed, one warning | Not run | No event-loop or IME execution claim; compare before replacement | [Pinned fork](https://github.com/wzzc-dev/window/tree/b33c9f0ac85002bca4a9cceccbbcd512d13b7ceb) |
| Handles | HWND/HINSTANCE bridge arguments | Fork workspace `Milky2018/windowing@0.1.0` | Compatible handles and ownership | Included in window check | Not run | Matching version names do not prove fork/registry source equality | Same pinned fork |
| Layout | No general engine selected | `Milky2018/chicle` checkout version `0.6.0` | Typed tree/style, measurement and invalidation | Native type check passed | Upstream tests: 80/80 JS and 80/80 WasmGC; no browser integration | Next: project-specific typed layout tests; no JSON UI DSL adoption | [Pinned source](https://github.com/moonbit-community/chicle/tree/d517dbfde05b42ad2f4b83242b4947043ec864cb) |
| Text | Shared MoonBit raster package and position validation | Published `Milky2018/moon_cosmic@0.3.3` plus pinned source comparison | Japanese/emoji/fallback, shaping and editing positions | Japanese layout, CPU glyph output and DX12 texture drawing/readback passed | JS/WasmGC editable-input GPU images agree; JS DPR-2 and font failure checks pass | Adopted for this bounded browser raster path; native interactive text, fallback and editing still required | [Font-backed evaluation](text-layout.md) |
| Async scripts | Incremental PS/MJS migration | Published `moonbitlang/async@0.21.2` | Files, subprocesses and exit handling | Native UI integration not established | `.mbtx` default runtime executes toolchain and GPU orchestration on Windows | Script success does not establish UI event-loop integration | `scripts/doctor.mbtx`, `scripts/verify-wgpu-binding.mbtx` |

The window fork default branch was `moui-support` at inspection. Its workspace
contains `modules/window` and `modules/windowing`; it is not interchangeable with
the upstream macOS-oriented window implementation. Its native check includes
MoonBit sources and does not compile/link/execute Win32 C or validate presentation.

The text checkout declares `moon_swash@0.1.10`, `moon_zeno@0.1.3`,
`moon_skrifa@0.1.8`, `moonbitlang/x@0.4.45`, and
`moonbit-community/harfbuzz@0.1.0`. Inspect the actual shaping path and target
requirements before assuming a pure MoonBit dependency graph.

Commands used with `MOON_HOME` and the explicit compiler from `toolchain.json`:
`moon check --target native` in each pinned checkout; additionally
`moon test --target js` and `moon test --target wasm-gc` in chicle and moon_cosmic.
The cloned sources were not patched. Warnings were retained, not treated as
proof of incompatibility or silently disabled.

## Follow-up selection

The initial table above is historical evidence, not the current task list. Its
layout row records the 2026-09-06 comparison against Chicle 0.6.0, before the
shared list was implemented. The current-boundary table and [ADR 034](../adr/034-shared-list-layout.md)
record the scoped adoption of Chicle 0.6.1. Open Issues own current priority and
acceptance criteria.

- GPU: retain the adopted binding and integrated event loop. Track further
  surface-reuse and presentation coverage separately from completed host migration.
- Layout/text: Chicle 0.6.1 is adopted behind `core/layout.VerticalList` for
  fixed-height vertical rows, clipping, pixel scrolling and focus reveal, and
  behind `layout_linear` for fixed/fill composition. Content measurement,
  automatic responsive rules and list virtualization remain unprovided.
  The independent Notes application still uses explicit bounds and has not
  migrated to this API. See [ADR 034](../adr/034-shared-list-layout.md) and the
  [application entry](../application-entry.md). Evaluate moon_swash/moon_zeno
  through text dependencies before creating separate public APIs. Preserve
  UTF-16/UTF-8/scalar validity requirements.
- Accessibility: the official AccessKit C adapter is adopted and production UIA
  behavior has automated evidence. `Milky2018/moon_accesskit` is not adopted;
  further data-model reuse must preserve that OS adapter and semantic contract.
  Actual assistive-technology acceptance remains separate.
- Browser: retain the adopted WebSys path and its JS/WasmGC comparison. Further
  reductions concern the remaining startup/presentation and buffer
  adapters; `mizchi/js_browser` has not been selected as an additional runtime.
- RPC: the integrated UI uses standard HTTP/JSON. Protobuf/gRPC remains an optional
  adapter evaluation, not a prerequisite for that path or the P0 application.

MoUI and Kagura are integration references, not selected framework dependencies.
Additional candidates are pending investigation, not rejected. Adoption decisions
will update only relevant ADR/dependency sections after comparison evidence exists.
