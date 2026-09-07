# Existing MoonBit GPU binding evaluation

Date: 2026-09-06. Evaluation is ongoing; the custom Rust wrapper is not a final
selection over the existing MoonBit binding.

## Pinned candidate

- Repository: [moonbit-community/wgpu-mbt](https://github.com/moonbit-community/wgpu-mbt).
- Inspected commit: `5b0608223bc491688a6f0f41492f23682717bc3b`.
- Module: `Milky2018/wgpu_mbt`, version 0.16.0, Apache-2.0.
- Dependency: `Milky2018/windowing@0.1.0`.
- Upstream native library: wgpu-native v29.0.1.1.
- Windows asset: `wgpu-windows-x86_64-msvc-release.zip`.
- SHA256: `7e67d7445c42aeb85e30f88930fd8d7d83ee769e3390aeb1ada75ebf3cf78132`.

The original ADR compared wgpu-native and a custom Rust wrapper without evaluating
this MoonBit binding. That comparison was incomplete. A smaller custom C ABI was
a convenience for the probe, not evidence that the existing binding was unsuitable.

## Observed results

With the project's pinned MoonBit compiler, `moon check --target native` passed
with seven upstream warnings. After preparing the pinned native asset,
`moon test --target native src/tests_windows` passed all three tests using MSVC
17.5.3 and static linking. The suite's platform guard queries Windows; its compute
smoke explicitly requests Vulkan and submits a compute pipeline. The other tests
cover Windows surface descriptors and invalid handles.

That upstream suite alone does not establish DX12, rectangle pixels, or live
HWND presentation. The upstream [platform status](https://github.com/moonbit-community/wgpu-mbt/blob/5b0608223bc491688a6f0f41492f23682717bc3b/docs/platform_support_status.md)
also distinguishes these missing presentation checks from its headless coverage.

The isolated `experiments/wgpu_binding` module now exercises the published
`Milky2018/wgpu_mbt@0.16.0` package with DX12 explicitly requested and asserted.
Four RGBA8 rectangle cases (640×360 twice, 317×193, and 1×1) check every pixel
against independently calculated colors with a one-channel rounding tolerance.
Rows use 256-byte alignment; padding is excluded from pixel comparisons.
Resources are released with `defer`. Both NVIDIA GeForce RTX 3060 and Microsoft
Basic Render Driver passed all four cases locally on 2026-09-06.

Run `mise run native:binding`; set `METONIC_GPU_FALLBACK=1` for the fallback
adapter. The task runs `scripts/verify-wgpu-binding.mbtx`, which downloads and
hash-checks the fixed asset, extracts it, prepares MSVC, and runs the native test.
The generated, ignored `.work/wgpu-assets/vs-env.cmd` only calls Microsoft's
environment setup and returns environment variables. Orchestration is MoonBit;
the candidate's external CommonJS prebuild remains unchanged. The nested
`package.json` establishes that CommonJS boundary.

This establishes equivalent pixels for the tested offscreen cases. It does not
establish equivalent failure handling or bounded completion. The existing command
host and Rust baseline remain intact while lifetime, integration and distribution
requirements are compared.

## Hidden HWND comparison

The same isolated module now includes the existing Win32 C host through a small
test stub. Two getters expose HINSTANCE/HWND to the binding. The test never calls
the host's Rust renderer loader: MoonBit creates the DX12 adapter, surface,
pipeline, uniform buffer and render commands through wgpu_mbt instead.

The test requires `METONIC_WINDOW_TEST=1` before creating the window; the `.mbtx`
runner sets it explicitly. It presents an initial 640×360 frame, processes a
right-arrow message, resizes to 317×193, clamps the rectangle to (197,121),
activates it with a pointer message and processes close. It checks the expected
event sequence and stable surface format. Each successful frame includes
acquisition, command submission and successful presentation. Both local adapters
passed, each reporting six frames and two passing tests including offscreen.

Per-frame views/commands are released before the next frame. The cleanup order
in the test releases render resources, unconfigures/releases the surface, releases
GPU objects, then destroys the HWND. A passing run exercises normal cleanup;
device-loss recovery and injected failure cleanup are not yet tested. The probe
does not observe visible compositor pixels, real input, DPI, IME or accessibility.

The runner cleans only the isolated module's build output before testing because
the C stub includes files outside that module and stale native objects must not
mask host changes. An async 120-second timeout bounds clean/test orchestration;
CI also imposes its three-minute step limit. This is not proof that every possible
descendant process is reclaimed on timeout.

## Build integration findings

The binding probe additionally uploads the MoonBit font raster and draws it through
a sampled-texture pipeline. Both adapters passed full readback comparisons; see
the [font and GPU text evaluation](text-layout.md). The renderer baseline remains
unchanged while interactive integration proceeds.

The unchanged upstream checkout was evaluated outside metonic's ESM package
directory. Inside that directory, its CommonJS `build.js` inherited the parent's
`type: module` and failed before compilation. A package boundary is needed when
integrating this prebuild hook; this is not a GPU failure.

With the dependency in the root module, the hook also runs when building a Wasm
verification tool that does not import `native_gpu`. Keeping the asset override
only inside the native build subprocess is insufficient: the following Wasm
build falls back to upstream extraction. Root-module developer commands therefore
need the prepared asset and override environment even for non-native targets.
This is a build-time coupling, not a browser runtime dependency on native wgpu.

The hook's Windows PowerShell archive expansion also failed in this environment.
Downloading the pinned release, verifying its SHA256 and extracting it with `tar`
allowed use of the existing `MBT_WGPU_NATIVE_ROOT` override. No binding source
patch was needed. `MBT_WGPU_LINK_MODE=static` selected static linking.

Observed warnings included C4819 source code-page warnings, MoonBit syntax/cleanup
warnings, and an ignored `-lvulkan-1` MSVC option. The tests nevertheless ran;
warnings must be addressed or scoped before integrating strict project checks.

## Next acceptance

The root `native_gpu` package now composes the binding with a persistent
rectangle pipeline and bounded readback. On 2026-09-07 its seven tests passed
with both the default and forced-fallback DX12 adapters using
`moon test native_gpu --target native --deny-warn --frozen` in the configured
MSVC/static-link environment. The suite includes the five callback contracts,
real GPU timeout/recovery, and renderer lifecycle. One renderer produces full
RGBA comparisons at 640x360, 317x193 and 1x1, rejects invalid inputs, recovers
after those errors, and rejects rendering after idempotent close. Adapter-name
access after close uses the retained string rather than a released native handle.

The native headless release executable also built successfully. These package
tests and compilation do not alone establish application transport or MCP
integration. The upstream C4819 source-code-page and ignored `-lvulkan-1`
warnings remain visible in MSVC output; MoonBit's `--deny-warn` is not an MSVC
warnings-as-errors policy.

The bounded readback comparison uses a caller-owned registry. Each GPU ticket
retains native references until its callback reaches a terminal state and clear
completes. A request timeout destroys its staging buffer and starts a separately
bounded cancellation drain. If completion remains pending, the registry keeps the
ticket and its native references; an error is not evidence of release. The caller
must retain and resolve those entries or terminate the owning process before
discarding that context. This is an experimental integration contract, not a
published library API.

Request polling yields through MoonBit async between nonblocking GPU polls. The
request timer and cleanup timer have separate polling budgets. The pinned async
native clock delegates to wall time, so these bounds are not described as a
monotonic deadline. A zero request polling budget provides a deterministic timeout
case without disabling the cleanup budget.

All eleven tests passed on both local adapters on 2026-09-07 after the rectangle
probe switched to this operation. Its four full-image comparisons remain intact.
An actual GPU request with zero polling budget times out, drains and clears, then
a fresh staging buffer reads a different payload on the same device. Callback
tests verify success, terminal errors, duplicate IDs, unresolved-ticket retention
and actual task cancellation. The cancellation test observes the original
cancellation error and exactly one cancel and one clear callback.

Source inspection on 2026-09-07 found that the synchronous readback helper in
`src/c/wgpu_stub_map.c` polls until its callback completes without a deadline.
The Rust baseline bounds device polling and result receipt at ten seconds each.
Replacing that call directly would lose an existing completion bound.

The resolved 0.16.0 dependency also uses unbounded `done_u32` polling in
`mbt_wgpu_instance_request_adapter_sync_ptr` and
`mbt_wgpu_adapter_request_device_sync_ptr` in `src/c/wgpu_stub_helpers_sync.c`.
The bounded readback operation does not cover these synchronous initialization
calls. A parent process deadline can terminate an unresponsive headless host;
an async timeout inside that host cannot interrupt a synchronous FFI call.
Interactive initialization requires separate event-loop and cancellation
evaluation. This source finding is not an observed initialization hang.

The candidate also exposes asynchronous submit/map, status, read and clear APIs.
In upstream commit `5b0608223bc491688a6f0f41492f23682717bc3b`,
`src/c/wgpu_stub_extras.c` leaves a pending map entry intact when clear is called;
buffer references and callback storage are reclaimed only after completion.
A timeout followed by clear alone is therefore insufficient cleanup. This source
finding does not demonstrate a runtime hang or leak on either tested adapter.

The recovery suite passed all five tests on both local adapters on 2026-09-07.
The synchronous probe checks exact range/alignment errors, subsequent known-byte
readback on the same device, repeated buffer allocation and a second device.
The asynchronous probe reads two payloads through the same staging buffer, then
destroys another buffer while its request is pending. Event pumping observes
`MAP_ASYNC_STATUS_ERROR`, clear removes its observable result, and a fresh staging
buffer reads successfully on the same device. Its wait loop uses nonblocking poll,
a ten-second wall-clock deadline and a 100,000-iteration cap; it does not call the
synchronous readback or blocking poll helpers.

This establishes the tested pending-buffer-destruction recovery path. It does not
inject an actual GPU stall or device loss, prove a monotonic production deadline,
or prove reclamation when callbacks never complete. Production integration must
preserve the deadline and define cleanup for that remaining case.

Extend failure cleanup and device-loss coverage, then compare integration and
distribution costs. Retain the existing renderer as the comparison baseline.
Record required C glue and toolchain dependencies. Prefer reusing the binding if
it meets these requirements; retain custom code only for demonstrated gaps.
Upstream's current JavaScript prebuild is an external dependency boundary, not
a reason to keep metonic's own orchestration in JavaScript.
