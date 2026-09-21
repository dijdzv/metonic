# Dependency record

Reconciled with the module manifests and preparation scripts on 2026-09-08.
Browser binding adoption and distribution were reconciled on 2026-09-13.

| Dependency | Pin | Purpose | License/distribution status |
| --- | --- | --- | --- |
| MoonBit toolchain | toolchain.json | Build and test tools; Windows x64 bootstrap | Downloaded from official distribution; not shipped with the application |
| MoonBit core | 0.10.12+1634b282e | Standard library; compiler/core pinned together | Bundled module declares Apache-2.0; review distribution notices before shipping |
| Node | 26.8.1 | Run generated JS in tests | Development only; not redistributed |
| pnpm | 12.3.4 | Locked development dependencies | MIT; development only |
| Playwright / playwright-core | 1.63.0 | Headless browser verification | Apache-2.0; development only |
| Chrome for Testing | 153.0.8010.12 / Playwright chromium 1243 | Headless WebGPU test browser | Downloaded by Playwright; not redistributed |
| MSVC / Windows SDK | environment.md | Native build prerequisites | Not redistributed by this repository |
| moonbitlang/async | 0.21.2 | Native application tasks, HTTP, cancellation and external-loop integration; process/file verification tools | Apache-2.0; native uses a prepared Windows waiter correction; browser UI scheduling uses its browser host, not this native runtime |
| mizchi/image / mizchi/zlib | 0.4.3 / 0.4.8 | Native PNG captures and MoonBit PNG validation in MCP/browser async/headless verifiers | Both Apache-2.0; earlier Wasm PNG interoperability was checked against pngjs; headless pixel migration removed that npm dependency; other image formats are outside this adoption |
| Milky2018/moon_cosmic | 0.3.3 | Shared text shaping/layout and raster experiments | Apache-2.0 module; transitive modules and font notices remain separate |
| Milky2018/wgpu_mbt | 0.16.0 | Native offscreen, window and worker rendering; isolated binding comparison | See the [binding record](wgpu-mbt.md) for its pinned native library boundary and notices |
| wzzc-dev/window and its windowing workspace | b33c9f0ac85002bca4a9cceccbbcd512d13b7ceb; window manifest 0.5.4-0.1.7 | Ordinary native window, input and event loop | Apache-2.0; pinned source plus pump/IME corrections prepared by `scripts/prepare-native-deps.mbtx`; not an unmodified registry package |
| dijdzv/websys | 71e7dbe57144cf88e569265a6c13776c853e2c16 | Browser input, GPU, HTTP, storage, font, timer and DOM placement bindings: upstream JS sources and generated WasmGC surfaces | MIT; `scripts/prepare-websys-input.mbtx` verifies the source archive; matching `websys-input.mjs` and `LICENSE-websys` ship in the browser package; generation uses source-pinned MoonBit and Bun 1.3.14, and the browser workspace uses the WebSys-reviewed official-async candidate |
| AccessKit C | 0.22.3 | Production Windows accessibility through the official C ABI | MIT OR Apache-2.0; locally built DLL includes focus/clipping corrections; both licenses copied beside the window executable; [build and boundary](native-accessibility.md) |
| Rust / Cargo | 1.93.0 | Build the patched AccessKit dependency | Build prerequisite, not a custom Metonic renderer or application runtime |
| @modelcontextprotocol/client and server / zod | 2.0.0 / 4.5.4 | Development MCP protocol and transport adapter | MIT; npm development dependencies, excluded from production UI artifacts |
| Microsoft winapp CLI | 0.6.0 | Opt-in owned-window presentation verification | MIT; downloaded with SHA256 verification, not shipped with the application; [capture scope](native-presentation.md) |

The manifests and resolved dependency records define the complete transitive
graph; this table identifies the principal build/runtime boundaries, not every
transitive package. Native application state, rendering orchestration and task
policy are MoonBit. The window dependency retains its OS implementation, and
Metonic retains the foreign-thread accessibility mailbox and wake thunk described
in the [reuse record](library-reuse.md). The custom Rust GPU renderer was removed.
The browser host uses the browser's WebGPU implementation through generated
WebSys bindings. Two host Promise functions preserve the existing asynchronous initialization contract; they do not implement GPU operations. The [browser input record](browser-input.md) describes preparation
and the callback-identity correction; the [reuse record](library-reuse.md)
separates adopted MoonBit responsibilities from remaining JavaScript adapters.
The npm dependencies remain development tools. Font selection and bundled notices are recorded in the
[text evaluation](text-layout.md). These adoption records do not establish real
IME or assistive-technology acceptance.

Before adopting a dependency, record version/commit, target support, license and
notices, and whether it is a build tool, production runtime, or development adapter.
metonic source is licensed under MIT OR Apache-2.0; third-party terms remain separate.

Browser async is pinned to official revision `a4cbfabbcdf4fa70ef28ad7ccc388082d92371de`
(module 0.22.1) with the reviewed WasmGC patch from the verified WebSys archive.
Preparation checks the revision and exact patch. This browser-only workspace
override does not change the native async version; `LICENSE-async` ships
with browser artifacts.

Native source preparation also removes obsolete production imports from the
pinned async and cosmic sources, retaining test-only imports in test scopes for
the updated compiler. These manifest corrections do not change runtime behavior;
preparation still rejects unexpected changes to the prepared source trees.
