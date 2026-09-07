# Library reuse evaluation

Date: 2026-09-06. This supplements dependency selection; it does not replace the
architecture or authorize adoption of every candidate. Working implementations
remain comparison baselines until equivalent requirements pass.

## Current boundaries

| Existing code | Responsibility | Reuse comparison |
| --- | --- | --- |
| `native_gpu/surface_renderer.mbt` | Shared HWND presentation and GPU resource lifetime | Adopted `Milky2018/wgpu_mbt`; custom Rust renderer removed |
| `examples/p0/native_window/bridge.c` | HWND, bounded event queue and lifetime | `wzzc-dev/window/windows`, raw handle compatibility |
| `examples/p0/native_window/async_workers.h` | Worker completion, cancellation and UI wakeup | `moonbitlang/async` public external-loop API; [integration decision](../adr/030-native-external-event-loop.md), existing worker evidence retained |
| `native_gpu`, `examples/p0/native_headless` | Persistent offscreen GPU resources, readback and capture | Adopted `Milky2018/wgpu_mbt@0.16.0`; headless C stub removed, stdio and file writing use MoonBit async |
| `examples/p0/browser/host/*.mjs` | WebGPU, DOM/input and host scheduling | Compare required calls against `mizchi/js_browser` and `bikallem/webapi` |
| `tools/devtools/*.mjs`, `scripts/*` | CLI/MCP transport and development verification | MoonBit orchestration first; external SDK adapters scoped separately |
| `examples/p0/text_position`, `semantics`, `task_scope` | Position validity, semantic actions and cancellation policy | Framework responsibilities; library presence does not replace these contracts |

`examples/p0` contains bounded architecture probes, not a supported public API.
Shared prototype packages currently live there so each experiment can reuse the
same contracts. Promote reusable implementations to library packages when their
responsibility and tests are established; keep demonstration hosts in examples.
Dependency experiments use isolated modules under `experiments` during comparison.
The Windows candidate now has a locally evaluated bounded-pump correction and
positive/negative contract comparison; see [event-pump results](windows-event-pump.md).
The initial checkout checks below remain historical results, not adoption claims.
The font-backed browser integration now uses a root `text_raster` package and pins
moon_cosmic in the root module. Demonstration hosts remain under `examples/p0`.

## Initial results

These are source-checkout results unless explicitly identified as published
package tests. Checkout version fields do not prove registry equivalence.

| Area | Current implementation | Candidate/version | Required behavior | Native result | Browser result | Gap and decision | Evidence |
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

## Remaining comparisons

- GPU: the existing hidden HWND host now isolates surface behavior before changing
  the event loop. Extend failure cleanup coverage and measure startup, transfers
  and distribution size before replacing the baseline.
- Layout/text: extend typed chicle and interactive text integration tests.
  Evaluate moon_swash/moon_zeno through text dependencies before creating separate
  public APIs. Preserve UTF-16/UTF-8/scalar validity requirements.
- Accessibility: compare `Milky2018/moon_accesskit` data model and updates with
  current semantics; verify Windows UI Automation independently. No OS adapter
  or current package version has been validated in this pass.
- Browser: inventory required WebGPU, input and semantic DOM calls before choosing
  `mizchi/js_browser` or `bikallem/webapi`; JS/WasmGC coverage must be demonstrated.
- RPC: inspect `moonbitlang/protoc-gen-mbt` generator/runtime compatibility before
  adding codec code. Native gRPC remains distinct from Node grpc-js bindings.

MoUI and Kagura are integration references, not selected framework dependencies.
Additional candidates are pending investigation, not rejected. Adoption decisions
will update only relevant ADR/dependency sections after comparison evidence exists.
