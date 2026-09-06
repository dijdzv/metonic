# ADR 024: Browser GPU comparison boundary

Date: 2026-09-06.

Status: rectangle experiment verified; production application backend selection remains open.

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

## References

The [verification record](../verification/browser-gpu.md) documents successful
headless runs with physical and software GPU adapters. Keep both application
targets in the experiment until text/async boundary evidence justifies narrowing
them. Use explicit SwiftShader selection in hosted CI and record it as software
rendering, separately from local physical-GPU results.

- [MoonBit exports and foreign libraries](https://docs.moonbitlang.com/en/latest/language/ffi.html#export-functions)
- [MoonBit package configuration](https://docs.moonbitlang.com/en/latest/toolchain/moon/package.html)
- [WebGPU specification](https://www.w3.org/TR/webgpu/)
