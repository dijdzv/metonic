# metonic

GPU-rendered UI and typed RPC for MoonBit.

metonic aims to let one MoonBit application run as a native Windows UI and in a
WebGPU browser. The UI runtime and RPC libraries are independent, so either can
be used without the other.

**Work in progress — not ready for production.** The current prototype connects
GPU rendering, text editing and HTTP/JSON RPC on Windows and in a browser. It is
not yet a usable UI framework; real IME, accessibility and distribution work
remain incomplete. Public APIs may change substantially.

## Direction

- MoonBit application code, fine-grained reactive state, and persistent UI nodes.
- Windows native and browser WebGPU rendering.
- Japanese text input, IME, keyboard navigation, and accessibility.
- A typed API contract shared by frontend and backend.
- First-class development automation through a CLI and MCP, excluded from production builds.
- MIT OR Apache-2.0.

The native prototype uses the official AccessKit adapter for production
accessibility nodes, actions and shared-editor text/selection patterns. Actual
assistive-technology usability and real IME acceptance remain incomplete;
see the [verification record](docs/verification/native-accessibility.md).
Development automation and production accessibility have separate responsibilities.

## Try the current prototype

The integrated demo runs a native GPU window and serves the browser UI from one
local HTTP server. Each UI owns its own editing state and uses the same typed
user-lookup endpoint; this is not synchronized editing between windows.

The browser defaults to WasmGC; JS remains available for comparison. The
[backend selection record](docs/verification/browser-target.md) explains the
measured tradeoff and the separate browser package.

On Windows x64, install [mise](https://mise.jdx.dev/), PowerShell 7 (`pwsh`), and
Visual Studio C++ x64 build tools with the Windows SDK. Native builds also require
Rust 1.93.0 (`rustc` and `cargo`) on PATH to build the pinned AccessKit dependency
with the reviewed local corrections. Select that toolchain before running the
commands below; the build rejects a different Rust version. See the
[Windows setup](docs/development.md#windows-x64-setup) for the full requirements.
From a checkout of this repository, run:

```powershell
mise trust
mise install
mise run bootstrap
mise run demo
```

Open the printed browser URL while the native window is running. In each UI:

1. Edit the main text and the **User ID** field (initially `1`).
2. Choose **Load user** and confirm `月兎` appears without replacing the editor.
3. Set User ID to `missing` to observe a domain error, then restore `1` and retry.
4. Try **Move after delay / Cancel**, resize, and continue editing. Native also
   provides **F5 / F6** for the delayed update and cancellation.

Closing the native window stops the shared server. The browser tab is
user-owned and stays open; its **Stop** button disposes that browser UI only.

The [demo walkthrough](docs/verification/integrated-demo.md) gives the common
operation sequence and current platform differences. The demo uses the packaged
browser UI; neither target is a finished product.

The bootstrap installs the pinned MoonBit toolchain into `.tools/moonbit`,
verifies download hashes, and bundles the standard library. It does not depend
on an older global MoonBit installation. The baseline is **MoonBit 0.10.11**,
checked against the current non-dev distribution on 2026-09-06.

For the browser probe and automated headless GPU checks:

```powershell
mise exec -- pnpm install --frozen-lockfile
mise run browser:install
mise run browser:headless
```

For native offscreen rendering, install the Visual Studio C++ build tools and run
`mise run native:headless`. It uses the published MoonBit wgpu binding. The separate
`mise run native:window` task verifies a hidden native window and its own-message
input sequence. Full setup and verification limits are in the development guide.

Node and pnpm run development verification, including Playwright and screenshot
inspection; neither is a native application runtime requirement. See the
[development guide](docs/development.md) for commands and test boundaries.

## Documentation

- [Architecture and scope](DESIGN.md)
- [Development guide](docs/development.md)
- [Development automation and accessibility](docs/adr/023-development-automation.md)
- [Verification results](docs/verification/p0.md)
- [Open tasks](https://github.com/dijdzv/metonic/issues)

## License

Copyright (c) 2026 dijdzv.

Licensed under either [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE), at your option.
