# Native headless GPU verification

Date: 2026-09-06.

The Windows offscreen probe connects MoonBit scene state to a Rust/wgpu DLL
through a small C ABI. It accepts JSON lines without opening a window. See
[ADR 025](../adr/025-native-headless-probe.md) for ownership and scope.

## Observed local results

The release build succeeded with MoonBit 0.10.11 and Rust 1.98.1 / wgpu 30.0.1.
The command-driven verifier passed complete RGBA pixel comparisons on both:

- NVIDIA GeForce RTX 3060, DX12, DiscreteGpu.
- Microsoft Basic Render Driver, DX12, Cpu, with forced fallback enabled.

Initial, moved, and activated frames were 640 x 360 (921,600 RGBA bytes each).
The resized frame was 317 x 193 (244,724 bytes), exercising removal of GPU row
padding. Each pixel was compared against the rectangle bounds and expected
background/foreground color, with a one-byte channel tolerance.

Stale revision rejection, malformed requests, invalid operations/dimensions,
oversized-line recovery, and normal shutdown passed. Missing bridge and missing
capture path returned capture failures without changing state or frame count.
EOF terminated successfully without an unsolicited response.

## Reproduction

Install the pinned project dependencies with `pnpm install --frozen-lockfile`.
Run `mise run native:headless` to build and verify the native probe.
Set `METONIC_GPU_FALLBACK=1` for the software adapter run.
PNG images, raw RGBA, adapter diagnostics, and JSON results are written below
`.work/native-headless/` and are not committed.

## Limits

This verifies offscreen rendering and command transport. It does not verify
window presentation, OS input, IME, accessibility, an MCP server, asynchronous
UI scheduling, or exclusion of development controls from a production build.
No desktop input automation was used. The software-DX12 run also passed on
Windows Server 2022 in [PR 15 CI](https://github.com/dijdzv/metonic/actions/runs/34028039826).
The implementation was integrated through [PR 15](https://github.com/dijdzv/metonic/pull/15).
