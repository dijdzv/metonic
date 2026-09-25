# Item and quote board

An independent source consumer for Metonic's Phase 5 public application API.
The first operation selects an item, obtains detail and stock together, then
starts a shipping quote from the coherent pair and quantity. Choosing USD
fetches an independent currency rate and converts the completed quote; the
JPY branch neither requests nor reads that rate. It has its own
common MoonBit model; the browser JS/WasmGC and Windows native entries use that
same model. Fixture delays make the two items complete detail and stock in
opposite orders. The USD multiplier of 2 is controlled test data, not a market
exchange rate.

The source is pinned by `dependency.json`. It is an experimental source
consumer, not a published Metonic package. Windows setup requires mise, Git,
Visual Studio C++ build tools and the framework prerequisites.

```text
mise trust
mise install
mise run deps:fetch
mise -C .metonic/framework trust
mise -C .metonic/framework run bootstrap
mise exec -- pnpm install --frozen-lockfile
mise exec -- pnpm exec playwright install chromium
mise run build:browser
mise run build:native
mise run run:native
mise run verify:model
mise run verify:browser
mise run verify:native
```

The browser output is `browser/.metonic-dist`; serve it over HTTP and select
`?target=js` or `?target=wasm-gc`. The native release executable is under
`native/.metonic-build/native/release/build/local/metonic_quote_native/main`.
Source builds invoke the pinned framework's public `application-source.mbtx`
entry and do not edit its internal workspace or host packages. The selected
item owns detail and stock requests; its keyed detail child owns the shipping
quote and display publication. `Toggle detail` removes or recreates that child
while keeping the selected item's completed data. Note saving and a
distribution package remain in the parent
[Issue #591](https://github.com/dijdzv/metonic/issues/591).

The model checks assert both A/B completion orders, rejection of an old D
result after quantity changes, child removal/recreation during an unfinished
quote, and independent currency completion and invalidation. The browser check
runs a real HTTP server and
headless Chromium on JS and WasmGC, saving stage screenshots in the ignored
`verification-output` directory. The native check owns a hidden window and
checks visible states, rendered pixels, operation dispatch and cleanup. These
checks do not establish physical IME behavior or clean-machine installation.

The generated `moon.work` files include framework and prepared dependency
packages. Scope formatting to application paths, for example
`moon -C browser fmt ../common/board app/main`; workspace-wide formatting would
change the pinned framework and make the source-entry integrity check fail.
