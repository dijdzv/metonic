# Development-only DX12 display feedback

Status: opt-in development integration; not selected by ordinary asset preparation
or release builds.

## Preparation

With the repository's MoonBit toolchain, Git, Cargo/MSVC build prerequisites and
`LIBCLANG_PATH` pointing to a directory containing `libclang.dll`, run
`moon run scripts/prepare-display-feedback.mbtx` from the repository root.
The script checks out the pinned source, applies exactly this patch, initializes
only the required WebGPU headers and builds the opt-in feature. Unexpected source
changes are rejected rather than overwritten. Both fresh preparation and reuse of
the patched source have been exercised.

The source is under `.work/wgpu-display-feedback/source`; Cargo's normal target
directory contains the resulting debug DLL and import library. An explicit
`CARGO_TARGET_DIR` may reuse an existing build cache. These outputs are not copied
over the ordinary release assets or selected by the application automatically.

## Integrated verification

With the same prerequisites and the repository's Node dependencies installed,
run `mise run native:window-display`. This builds `window_display_dev`, then
verifies editing, `wait_display` and capture of that exact retained frame through
the line protocol, attached CLI and the MCP SDK on default and fallback adapters. It opens
dedicated windows; a functioning visible display is required for positive evidence.
The script selects the same DLL path for both the GPU binding and the extension.
Ordinary `window_dev` shares the control implementation but supplies no reader.

The host build generates an import library containing only
`metonicSurfaceReadDisplayFeedback`. Importing the full wgpu export library would
collide with the MoonBit binding's dynamic-loader definitions. The GPU API still
loads through that binding, with both paths selecting the same adjacent DLL.

The CLI case starts an independently owned development window, attaches using
its discovery file, edits text, waits for the exact retained frame and checks
confirmed capture metadata. Closing the CLI leaves the app running. An owned
window-close request then verifies normal exit and discovery removal.

`wait_display` takes `frame_scope`, decimal Int64 `frame_id`, and `timeout_ms`
(1–60000). It returns success only for exact-ID confirmation. Invalid, future,
evicted, unavailable and invalidated-epoch frames return explicit errors; pending
frames expire at their deadline. Poll requests are serialized on the UI event
queue. Each active waiter samples at 16-ms intervals and stops on completion,
cancellation or shutdown. Concurrent waits currently have separate timers.

MCP exposes `window_wait_display`; `window_capture_retained` reports the confirmed
flag with image metadata. `window-mcp.mjs --display` selects the dedicated host
and permits its GUI window to appear. Its process environment must select that
host's adjacent `wgpu_native.dll` via `MBT_WGPU_NATIVE_LIB` and set
`MBT_WGPU_NATIVE_ALLOW_UNVERIFIED=1` for the locally patched library. The verification
task supplies both. The normal MCP launch keeps its existing hidden-launch option.

## Boundary

Base: `gfx-rs/wgpu-native` commit
`6aed50955d934ac36049ba8d002034841633ae02` (29.0.1.1).

The patch adds the opt-in Cargo feature `metonic-display-feedback`, which enables
DX12 and exports `metonicSurfaceReadDisplayFeedback` on Windows. Builds without
the feature do not include the extension. The ordinary upstream SurfacePresent
behavior is unchanged. No window display, diagnostic sleeps, environment-variable
hooks or test fixtures are included in this patch.

The native boundary is necessary because the published C API does not expose
the actual DX12 swap chain's presentation statistics. The extension uses the HAL
accessor without private-layout casts, a second swap chain or escaping COM
pointers. MoonBit remains responsible for image identity, epochs, deadlines,
cancellation and scheduling. This is a candidate for an upstream presentation
feedback proposal; no upstream submission has been made.

The caller must supply a live surface and valid aligned writable storage and
serialize calls with present, configure, unconfigure and final surface release.
The output is 24 bytes on Windows x64: two UInt32 present counts, an Int64 QPC
sample and two UInt32 refresh counts, in that order. A borrowed three-element
MoonBit FixedArray[Int64] supplies aligned storage without an extra C bridge.

Return values are 0 for a retrieved sample, 1 for unavailable, -1 for a null
argument, or the DXGI HRESULT. Failure clears the sample, except that the last
present count remains when it was acquired before a statistics error. In
particular, DISJOINT can preserve the ID while invalidating statistics.

Success alone is not display confirmation: zero statistics remain unconfirmed.
Only a valid exact-ID observation can confirm the associated target. A newer ID
does not prove that an earlier frame appeared. Configuration changes, DISJOINT,
counter wrap and image eviction need explicit handling by the caller. QPC is a
synchronization sample, not an exact image scanout timestamp.

The precursor implementation passed an actual MoonBit/native ABI test. The
extracted optional feature then built from the fixed upstream checkout with its
pinned WebGPU headers (`673658bc2bd70ec39fc55ebe6bb0173cf6d0a603`) and passed
visible Surface observations on default and fallback adapters through MoonBit.
DLL export verification passed with the feature disabled and enabled: the
feedback symbol appears only when enabled, ordinary `wgpuSurfacePresent` remains
available in both builds, and neither diagnostic nor ABI-fixture entry points
are exported. Integrated wire and MCP wait/capture have also passed on both
adapters. The ordinary production exclusion verifier checks the generated code,
link inputs and existing binary/IME boundaries; display status and control-package
markers are absent from the release application. Physical presentation evidence depends on
the display environment; hidden-window lifecycle success is not display proof.
