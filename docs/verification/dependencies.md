# Dependency record

Recorded: 2026-09-06.

| Dependency | Pin | Purpose | License/distribution status |
| --- | --- | --- | --- |
| MoonBit toolchain | toolchain.json | Build and test tools; Windows x64 bootstrap | Downloaded from official distribution; not shipped with the application |
| MoonBit core | 0.10.11+6ff76a5f9 | Standard library; native/JS/WasmGC tested | Bundled module declares Apache-2.0; review distribution notices before shipping |
| Node | 26.8.1 | Run generated JS in tests | Development only; not redistributed |
| pnpm | 12.3.4 | Locked development dependencies | MIT; development only |
| Playwright / playwright-core | 1.63.0 | Headless browser verification | Apache-2.0; development only |
| pngjs | 7.0.0 | Inspect rendered screenshot pixels | MIT; development only |
| Chrome for Testing | 153.0.8010.12 / Playwright chromium 1243 | Headless WebGPU test browser | Downloaded by Playwright; not redistributed |
| MSVC / Windows SDK | environment.md | Native build prerequisites | Not redistributed by this repository |

No external Mooncakes modules or Rust crates are used by the current prototype.
The browser host uses the browser's WebGPU implementation. The npm dependencies
above are test tools, not application assets. AccessKit, native GPU, text, fonts,
and network implementation libraries remain candidates.

Before adopting a dependency, record version/commit, target support, license and
notices, and whether it is a build tool, production runtime, or development adapter.
metonic source is licensed under MIT OR Apache-2.0; third-party terms remain separate.
