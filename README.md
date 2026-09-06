# metonic

GPU-rendered UI and typed RPC for MoonBit.

metonic aims to let one MoonBit application run as a native Windows UI and in a
WebGPU browser. The UI runtime and RPC libraries are independent, so either can
be used without the other.

**Work in progress — not ready for use.** The current code is limited to technical
prototypes; a usable GPU UI framework and network RPC transport are not implemented
yet. Public APIs may change substantially.

## Direction

- MoonBit application code, fine-grained reactive state, and persistent UI nodes.
- Windows native and browser WebGPU rendering.
- Japanese text input, IME, keyboard navigation, and accessibility.
- A typed API contract shared by frontend and backend.
- First-class development automation through a CLI and MCP, excluded from production builds.
- MIT OR Apache-2.0.

AccessKit is under evaluation for the native accessibility adapter; it is not
an adopted dependency. Development automation and production accessibility have
separate responsibilities.

## Try the current prototype

The current prototype checks typed procedure contracts on native, JavaScript,
and WasmGC. It binds handlers in-process; it does not make network requests.

On Windows x64, install [mise](https://mise.jdx.dev/), PowerShell 7 (`pwsh`), and
Visual Studio C++ build tools with the Windows SDK, then run:

```powershell
mise trust
mise install
mise run bootstrap
mise run verify
mise run verify-native
```

The bootstrap installs the pinned MoonBit toolchain into `.tools/moonbit`,
verifies download hashes, and bundles the standard library. It does not depend
on an older global MoonBit installation. The baseline is **MoonBit 0.10.11**,
checked against the current non-dev distribution on 2026-09-06.

Node is used to run generated JavaScript during verification. There are no npm
dependencies. If JavaScript packages become necessary, pnpm will manage them;
neither Node nor pnpm is a native application runtime requirement.

## Documentation

- [Architecture and scope](DESIGN.md)
- [Development guide](docs/development.md)
- [Development automation and accessibility](docs/adr/023-development-automation.md)
- [Verification results](docs/verification/p0.md)
- [Open tasks](https://github.com/dijdzv/metonic/issues)

## License

Copyright (c) 2026 dijdzv.

Licensed under either [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE), at your option.
