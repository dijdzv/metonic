# Verification environment

Recorded: 2026-09-06. This is a reproducibility record, not the minimum supported
hardware specification.

| Component | Verified value |
| --- | --- |
| OS | Windows 11 Pro, 10.0.26200, x64 |
| GPU | NVIDIA GeForce RTX 3060 |
| GPU driver | 32.0.16.1047 |
| mise | 2026.8.5 windows-x64 |
| PowerShell | 7.6.5 (local); PowerShell 7 on hosted CI |
| Node | 26.8.1 |
| MoonBit compiler/core | 0.10.11+6ff76a5f9 |
| moon / moonrun | 0.1.20260827, d0aaa07 |
| Visual Studio | 2022 Community; DevShell 17.5.3 |
| Windows SDK include | 10.0.22000.0 |
| Headless browser | Chrome for Testing 153.0.8010.12, Playwright 1.63.0 |
| Browser WebGPU | JS/WasmGC rectangle, input, resize, idle, stop verified headlessly |
| Native GPU / IME execution | Not yet tested |

## Toolchain provenance

The current non-dev distribution was checked on 2026-09-06. Versioned compiler
and core URLs resolve to the same archives as the current distribution.
URLs and SHA256 values are committed in `toolchain.json`.

The compiler archive hash was compared with the official published SHA256.
The core hash was recorded from the official HTTPS artifact and checked against
the versioned artifact; no separately signed core manifest was verified.

The bootstrap downloads into a fresh staging directory, validates hashes, bundles
the core library, validates the reported version, and then installs it under
`.tools/moonbit`. Global MoonBit settings are not used by verification tasks.

## Migration findings

Moving from compiler 0.7.2 to 0.10.11 required `Show` derives to become `Debug`
and configuration migration to `moon.mod` / `moon.pkg`.
The formatter also selects the current executable-package syntax.

The native verification script explicitly loads a Visual Studio developer
environment and selects MSVC. On this machine, direct DevShell module loading
avoids a localized JSON parsing failure in `Launch-VsDevShell.ps1`.
Compiler diagnostics use `VSLANG=1033`.

## Interpretation

Native results remain console tests. The shared scene and RPC tests also run in
Node and moonrun. The separate browser probe verifies an actual WebGPU rectangle
through headless Chromium; it does not demonstrate a full UI framework, IME, or an
OS accessibility provider. GPU identification alone is not a rendering test.
