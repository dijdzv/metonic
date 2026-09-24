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

These checks ran on Windows 11 Pro 10.0.26200 with pinned Moon
`0.1.20260904`, Node 26.8.1 and a Windows x64 native toolchain. They establish
source-entry builds, native start/close and browser artifact presence, not a
clean-machine installation, interactive editing in the packaged Notes UI,
another OS/browser/driver, or an upstream fix.
The local release gate still requires the normal native/browser input,
persistence, resource and packaged-artifact regressions on the integrated
revision. A future pinned `wgpu_mbt` release with explicit `.cjs` prebuilds
should remove the temporary scope marker.
