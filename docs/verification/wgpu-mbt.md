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

This proves the candidate can replace the custom bridge for this offscreen
operation. It does not yet justify replacing the working HWND renderer or its
command host. Interactive asynchronous completion, surface teardown/resize,
distribution size, and comparative timing remain unverified.

## Build integration findings

The unchanged upstream checkout was evaluated outside metonic's ESM package
directory. Inside that directory, its CommonJS `build.js` inherited the parent's
`type: module` and failed before compilation. A package boundary is needed when
integrating this prebuild hook; this is not a GPU failure.

The hook's Windows PowerShell archive expansion also failed in this environment.
Downloading the pinned release, verifying its SHA256 and extracting it with `tar`
allowed use of the existing `MBT_WGPU_NATIVE_ROOT` override. No binding source
patch was needed. `MBT_WGPU_LINK_MODE=static` selected static linking.

Observed warnings included C4819 source code-page warnings, MoonBit syntax/cleanup
warnings, and an ignored `-lvulkan-1` MSVC option. The tests nevertheless ran;
warnings must be addressed or scoped before integrating strict project checks.

## Next acceptance

Port the HWND lifetime probe to this binding, preserving adapter identification,
resize and teardown checks. Retain the existing renderer as the comparison baseline.
Record required C glue and toolchain dependencies. Prefer reusing the binding if
it meets these requirements; retain custom code only for demonstrated gaps.
Upstream's current JavaScript prebuild is an external dependency boundary, not
a reason to keep metonic's own orchestration in JavaScript.
