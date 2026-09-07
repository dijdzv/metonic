# Native headless GPU verification

Date: 2026-09-07.

The Windows offscreen probe connects MoonBit scene state to the root `native_gpu`
package using `Milky2018/wgpu_mbt@0.16.0` and statically linked wgpu-native
29.0.1.1. It accepts JSON lines without opening a window. See
[ADR 025](../adr/025-native-headless-probe.md) for ownership and scope.

## Observed local results

The release build succeeded with MoonBit 0.10.11 and the pinned MSVC native asset.
The command-driven verifier passed complete RGBA pixel comparisons on both:

- NVIDIA GeForce RTX 3060, DX12, DiscreteGpu.
- Microsoft Basic Render Driver, DX12, Cpu, with forced fallback enabled.

Initial, moved, and activated frames were 640 x 360 (921,600 RGBA bytes each).
The resized frame was 317 x 193 (244,724 bytes), exercising removal of GPU row
padding. Each pixel was compared against the rectangle bounds and expected
background/foreground color, with a one-byte channel tolerance.

Stale revision rejection, malformed requests, invalid operations/dimensions,
oversized-line recovery, and normal shutdown passed. Empty and relative capture
paths, and a directory used as the output file, returned capture failures without
changing state or frame count. A second complete rendering session passed with
`METONIC_GPU_BRIDGE` pointing to a missing file, verifying that this executable
does not need the old custom DLL. This replaces the old DLL-loader failure test;
it is not an injected GPU-device failure.
EOF terminated successfully without an unsolicited response.

On 2026-09-07 the MoonBit verifier passed these scenarios on both adapters after
the binding integration. Earlier baseline verification using independent pngjs
decoding also matched every expected pixel in all eight output
images: 230400 pixels for each 640x360 capture and 61181 for each resized capture.

## Reproduction

The verifier in `tools/verify_native_headless` uses a test-only raw process
transport. Invalid versions, malformed JSON and oversized lines must reach the
native parser unchanged; the normal control client rejects these before sending.
The raw transport bounds response lines and stderr, applies request and shutdown
deadlines, and rejects trailing output. PNG encoding reuses `mizchi/image`.

Complete the toolchain setup in the [development guide](../development.md).
Run `mise run native:headless` to build and verify the native probe.
Set `METONIC_GPU_FALLBACK=1` for the software adapter run.
PNG images, raw RGBA, adapter diagnostics, and JSON results are written below
`.work/native-headless/` and are not committed.

## Native standard I/O

The native probe uses the pinned MoonBit async stdio implementation and the shared
bounded line framer. Its LF mode accepts LF and CRLF, preserves CR inside JSON
whitespace, and limits the body to 4095 bytes. Oversized lines are drained before
the next request; invalid UTF-8 is rejected separately from invalid JSON. A final
unterminated request is processed once at EOF.

Successful shutdown stops buffered requests as well as further reads. A rejected
shutdown request leaves the session available. GPU and semantic resources are
released through `defer` when the loop ends. The removed C functions handled line
reading, UTF-8 conversion and response writing. GPU composition and capture-file
writing have also moved to MoonBit, and the headless C stub is removed. The
upstream binding still contains the C ABI required by wgpu-native.

The LF framing changes passed all nine framing tests. The native verifier passed
on both GPU modes with 4095-byte LF/CRLF requests, 4096-byte rejection and recovery,
invalid UTF-8 recovery, fragmented CRLF, embedded CR whitespace, batched requests,
an unterminated final request and rejected shutdown recovery. A shutdown followed
by another buffered request produces only the shutdown response. After a capture,
closing stdout and requesting another response ends the process with exit code
zero while stdin is still open; this checks the output-error exit path separately
from ordinary EOF. The original four GPU captures and failure cases remain in
the same verification run, with DLL-loader failure replaced by static-link
independence and output-file failure coverage.

## Limits

This verifies offscreen rendering and command transport. It does not verify
window presentation, OS input, IME, accessibility, an MCP server, asynchronous
UI scheduling, or exclusion of development controls from a production build.
No desktop input automation was used. The software-DX12 run also passed on
Windows Server 2022 in [PR 15 CI](https://github.com/dijdzv/metonic/actions/runs/34028039826).
The implementation was integrated through [PR 15](https://github.com/dijdzv/metonic/pull/15).
