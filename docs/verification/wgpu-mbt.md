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

This does not establish DX12, rectangle pixels, asynchronous readback, or live
HWND presentation. The upstream [platform status](https://github.com/moonbit-community/wgpu-mbt/blob/5b0608223bc491688a6f0f41492f23682717bc3b/docs/platform_support_status.md)
also distinguishes these missing presentation checks from its headless coverage.

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

Port the current rectangle readback and HWND lifetime probes to this binding,
preserving pixel comparisons, adapter identification, resize and teardown checks.
Record required C glue and toolchain dependencies. Prefer reusing the binding if
it meets these requirements; retain custom code only for demonstrated gaps.
Upstream's current JavaScript prebuild is an external dependency boundary, not
a reason to keep metonic's own orchestration in JavaScript.
