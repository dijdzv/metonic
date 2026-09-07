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
| moonbitlang/async | 0.21.2 | Host-side process, file and HTTP development tools | Apache-2.0; native/Wasm host use does not establish browser WasmGC support |
| mizchi/image / mizchi/zlib | 0.4.3 / 0.4.8 | Native PNG captures and MoonBit PNG validation in MCP/browser async verifiers | Both Apache-2.0; Wasm PNG interoperability checked against pngjs; other image formats are outside this adoption |
| Milky2018/moon_cosmic | 0.3.3 | Shared text shaping/layout and raster experiments | Apache-2.0 module; transitive modules and font notices remain separate |
| Milky2018/wgpu_mbt | 0.16.0 | Native offscreen, window and worker rendering; isolated binding comparison | See the [binding record](wgpu-mbt.md) for its pinned native library boundary and notices |

Direct dependency pins above were reconciled with the module manifests
on 2026-09-07. The manifests and resolved dependency records define the complete
transitive graph. The browser host uses the browser's WebGPU implementation; npm
dependencies remain development tools. AccessKit has not been adopted. Font
selection and bundled notices are recorded in the [text evaluation](text-layout.md).

Before adopting a dependency, record version/commit, target support, license and
notices, and whether it is a build tool, production runtime, or development adapter.
metonic source is licensed under MIT OR Apache-2.0; third-party terms remain separate.
