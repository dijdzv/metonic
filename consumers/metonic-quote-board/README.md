# Item and quote board

An independent source consumer for Metonic's Phase 5 public application API.
The first operation selects an item, obtains detail and stock together, then
starts a shipping quote from the coherent pair and quantity. Choosing USD
fetches an independent currency rate and converts the completed quote; the
JPY branch neither requests nor reads that rate. It has its own
common MoonBit model; the browser JS/WasmGC and Windows native entries use that
same model. Fixture delays make the two items complete detail and stock in
opposite orders. The USD multiplier of 2 is controlled test data, not a market
exchange rate. The fixture fails the first Blue stool quote at quantity 4;
Retry quote requests that same input once and then displays its result.

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
while keeping the selected item's completed data. The note editor and Save note
button belong to the application Scope. Each save captures its text and edit
revision; writes for this document complete in order even if the selected item
or detail disappears. The status shows unsaved, saving, saved and failed states.
Closing with unsaved text queues a save and waits for its acknowledgement. A
failed or rejected write keeps the app open so Save note can retry it. This
example uses an in-memory delayed storage fixture: it verifies save ordering
and acknowledgements, but does not restore text after a process restart. A
distribution package and the remaining end-to-end cases are tracked in
[Issue #591](https://github.com/dijdzv/metonic/issues/591).

The model checks assert both A/B completion orders, rejection of an old D
result after quantity changes, child removal/recreation during an unfinished
quote, independent currency completion and invalidation, explicit D failure
and retry, and serialized note saves after newer edits, child removal and close.
The browser check
runs a real HTTP server and
headless Chromium on JS and WasmGC, saving stage screenshots in the ignored
`verification-output` directory. The native check owns a hidden window and
checks visible states, rendered pixels, operation dispatch and cleanup. These
checks do not establish physical IME behavior or clean-machine installation.

For development diagnostics, build the separate browser entry, verify both
targets, then rebuild the normal browser entry before packaging:

```text
mise exec -- moon run build.mbtx -- browser-diagnostics
mise exec -- node verification/browser.mjs --diagnostics
mise run verify:browser
```

The development entry exposes bounded owner, Source, derived-state and Driver
events without recording note text or failure messages. The normal browser
entry has no diagnostics export; its verification checks that exclusion. The
native probe uses the same optional registry through the public window host.

The generated `moon.work` files include framework and prepared dependency
packages. Scope formatting to application paths, for example
`moon -C browser fmt ../common/board app/main`; workspace-wide formatting would
change the pinned framework and make the source-entry integrity check fail.
