# ADR 024: Browser GPU comparison boundary

Date: 2026-09-06.

Status: WasmGC selected for the P0 browser application on 2026-09-08; production packaging remains open.

## Context

P0-B must compare MoonBit JavaScript output with WasmGC using a real WebGPU
host. A console build cannot establish browser support, rendered output, input
handling, or resource lifetime. The comparison should isolate the application
backend instead of changing both the state implementation and renderer at once.

## Experiment

Compile the same small MoonBit scene state for both backends. It owns viewport
dimensions, rectangle position, activation, and a revision. A foreign-library
package exports initialization, resize, movement, activation, and integer field
reads. The browser host owns only browser/GPU resources and input scheduling.
It forwards input to MoonBit and derives GPU uniforms from the resulting state.

Both variants use the same HTML, CSS, JavaScript host, and WGSL shader. Render a
rectangle with a real GPU render pass, handle keyboard/pointer input and resize,
schedule frames only when invalidated, and release resources explicitly on stop.
Unsupported WebGPU, initialization errors, and device loss must be visible.

The host's DOM is a diagnostic harness. It is not a component renderer or the
production semantic DOM adapter. No remote-control global or MCP endpoint is
introduced by this experiment.

## Acceptance and interpretation

- Compile both release artifacts with the pinned toolchain and verify identical
  state transitions across their actual exported ABI, including clamping/reset.
- Test the shared MoonBit state independently on native, JS, and WasmGC.
- Verify a real headless browser GPU frame and input-driven changes for both
  variants through a repeatable command, without desktop input automation.
- Check resize, idle scheduling, and explicit cleanup; record unavailable tests.
- Record artifact bytes, initialization observations, and transfer boundaries.

The scalar field API is deliberately limited to one rectangle. It is not the
final scene transfer protocol: multiple nodes require batched transfer and
measurements before choosing a representation. GPU uniform uploads are copies;
this experiment makes no zero-copy claim.

Submission counts are not presentation acknowledgments. Future development
capture/frame barriers require stronger synchronization. A single small-module
initialization observation is not a performance benchmark or a backend selection
criterion by itself. Native ABI, text, IME, and accessibility are separate gates.

## P0 backend selection

The integrated text/editor/HTTP application selects WasmGC as its default browser
backend. JS remains an explicit comparison target, not an automatic fallback.
Both targets have passed the existing state, GPU pixels, text, asynchronous
updates, HTTP and shutdown checks in Chromium on the tested physical GPU and
SwiftShader. WasmGC has the smaller uncompressed application artifact with the
same current host/transfer contract. See [the current comparison](../verification/browser-target.md)
for sizes, reproduction and limits.

This decision is scoped to the verified P0 browser environment. It does not
claim broader browser compatibility, superior execution speed, physical IME
behavior or a completed production bundle. Missing WebGPU/WasmGC produces a
visible startup failure; the application does not silently choose another backend.
Production packaging must ship the selected artifact and exclude development
adapters while keeping normal DOM/input/GPU/HTTP boundaries. That work remains
open rather than being satisfied by changing the default query parameter.

## References

The [verification record](../verification/browser-gpu.md) documents successful
headless runs with physical and software GPU adapters. Keep both application
targets in the comparison suite so the P0 selection remains testable. Use
explicit SwiftShader selection in hosted CI and record it as software
rendering, separately from local physical-GPU results.

- [MoonBit exports and foreign libraries](https://docs.moonbitlang.com/en/latest/language/ffi.html#export-functions)
- [MoonBit package configuration](https://docs.moonbitlang.com/en/latest/toolchain/moon/package.html)
- [WebGPU specification](https://www.w3.org/TR/webgpu/)
