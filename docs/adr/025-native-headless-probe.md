# ADR 025: Native headless GPU and command probe

Date: 2026-09-06.

Status: proposed experiment; window and accessibility adapter choices remain open.

Review update: the initial comparison omitted `wgpu-mbt`. Its Windows compute
and surface-contract tests now pass locally; see the
[existing binding evaluation](../verification/wgpu-mbt.md). The custom wrapper
remains an experimental baseline while equivalent rendering is evaluated.

## Context and comparison

The next native experiment must be operable through a command interface without
desktop input automation. Begin with offscreen GPU rendering and image readback;
window presentation, OS input, IME, and accessibility require additional gates.

| Candidate | Boundary and tradeoff |
| --- | --- |
| wgpu-native 29.0.1.1 | Existing WebGPU C API and Windows binaries; requires C descriptor/callback/resource bindings and tracking the native header version |
| Small Rust wrapper over wgpu 30.0.1 | Small explicit C ABI for this probe; Rust owns GPU resources/readback and requires a pinned Rust toolchain and locked build dependencies |

Use the Rust wrapper for this bounded experiment. It lets the MoonBit/native
lifetime boundary be tested with a few functions while using the current Rust
wgpu API. This is not a comparative performance claim or a final adoption of a
windowing/text/accessibility stack. wgpu-native remains the C API alternative if
the custom bridge grows into unnecessary duplication.

## Ownership and composition

The existing MoonBit scene state remains the application state owner. A dedicated
`native_headless` executable accepts versioned, bounded JSON lines on stdin and
returns structured responses on stdout. It offers snapshot, move, resize,
activate, capture, and shutdown. An optional expected revision rejects stale
operations before mutation. Reset means starting a fresh process, avoiding reuse
of old revisions within one session.

The C stub owns UTF-8/UTF-16 conversion, bounded stdio, DLL lifetime, and writing a
capture to a launch-selected path. It does not implement application behavior.
The Rust library owns device/pipeline resources and writes tightly packed RGBA
pixels into a caller-owned buffer after GPU readback completes. It contains no
stdio command parser, capture-file writer, listener, or MCP implementation.

The DLL path is explicit and absolute. Do not search the current directory/PATH
for an interchangeable bridge. Load its dependencies only from the selected DLL
directory and Windows system directory. The probe is single-threaded; native
pointers are never public MoonBit UI state.

## Rendering and lifetime gates

Render the same rectangle meaning as the browser probe into RGBA8 texture data.
Validate dimensions and buffer lengths at the C/Rust boundary, pad GPU readback
rows to their required alignment, and strip padding before returning pixels.
Catch Rust panics at exported entry points and report failures rather than unwind
through MoonBit. Release the context before unloading the DLL, including EOF.

Only a completed readback increments the capture frame counter. Snapshot and
mutation commands do not poll or render implicitly. The command client can assert
pixel colors, bounds, and state changes without a visible window. Test stale
revision, invalid input, malformed/oversized requests, GPU failure, and teardown.

Blocking stdin and GPU readback are acceptable only in this headless probe.
They are not an approved implementation for the eventual interactive UI thread.
P0-C must establish queue/wakeup and asynchronous completion before that host.

## Remaining decisions

This establishes an automation boundary, not the final MCP schema or production
exclusion proof. An external MCP adapter can later reuse the command client;
production entry points must omit the control composition. Accessibility stays a
separate production adapter and is not represented by passing these tests.

No windowing crate is selected here. Compare the window/event bridge separately
and retain the headless path as an independent renderer test.

## References

- [wgpu-native release 29.0.1.1](https://github.com/gfx-rs/wgpu-native/releases/tag/v29.0.1.1)
- [wgpu 30.0.1 render-to-texture example](https://github.com/gfx-rs/wgpu/blob/v30.0.1/examples/features/src/render_to_texture/mod.rs)
- [MoonBit native FFI](https://docs.moonbitlang.com/en/latest/language/ffi.html)
