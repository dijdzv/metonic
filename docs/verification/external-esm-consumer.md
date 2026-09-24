# External ESM consumer builds

The source entry was checked against an independent copy of the tracked Notes
consumer at Metonic revision `a7e88c9`. Its root `package.json` declared
`{"type":"module"}` and its `.metonic/framework` path resolved to that clean
revision. The consumer's `dependency.json` pinned the same full revision.

With the published, unmodified `Milky2018/wgpu_mbt@0.16.0` package, the source
entry prepared the native workspace and built its `main` entry in release mode.
The resulting executable was present. The owned-window release probe launched
that external executable, observed its `Memo` window, and passed both normal
close and system-key close with GPU ownership released. The same entry
prepared and built the browser workspace in release mode; `app.mjs` and
`app.wasm` were present in the consumer distribution. Both workspace dependency
caches received
`{"type":"commonjs"}` at `.mooncakes/package.json`. The native cache still
contained the registry package's `build.js`, proving this check did not rely on
an edited GPU package.

Before this framework-managed marker was added, a separate minimal ESM
consumer with published `wgpu_mbt@0.16.2` failed `moon build --target native`
because Node treated `build.js` as ESM. Adding only the cache-root marker made
that same build pass. The source entry also rejected an existing native cache
marker with `{"type":"module"}` without overwriting it.

The source-entry correction was merged in [#581](https://github.com/dijdzv/metonic/pull/581).
The tracked independent Notes consumer now pins that merged revision and
declares `"type":"module"` in [#582](https://github.com/dijdzv/metonic/pull/582).
It passed native and browser release builds, browser and native verification,
the source contract, a fresh first-setup check, and all local pre-commit and
pre-push checks. [Clean Windows CI](https://github.com/dijdzv/metonic/actions/runs/36013320767)
passed on that consumer revision. The initial isolated checks ran on Windows 11
Pro 10.0.26200 with pinned Moon `0.1.20260904`, Node 26.8.1 and a Windows x64
native toolchain.

These checks establish the source-entry compatibility path, not a clean-machine
installation, another OS/browser/driver, or an upstream fix. The local release
gate still requires the final integrated native/browser input, persistence,
resource and packaged-artifact checks. A future pinned `wgpu_mbt` release with
explicit `.cjs` prebuilds should remove the temporary scope marker.
