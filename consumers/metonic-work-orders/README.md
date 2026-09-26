# Work orders: external application evaluation

This is an experimental Metonic consumer for Phase 6. It is an application
workspace with its own modules and entry packages, using the exact framework
revision in [`dependency.json`](dependency.json). It is not yet a complete
work-order product: changes are currently in memory, and remote data, durable
save, and platform-specific commands have not been added.

The first interaction is a searchable list of work orders. Selecting a row
shows its title and details; editing the title changes the row. The search
query belongs to the filter component, the orders and selection belong to the
document scope, and the closed-order setting belongs to the application scope.
The same `common/work_orders` application code runs in Windows native and in
browser JS and WasmGC.

## Build from the public source entry

Follow `docs/application-entry.md` in the pinned framework checkout: clone the
exact `dependency.json` revision into `.metonic/framework` and run
that checkout's `mise run bootstrap` once. Then, from that checkout, use its
pinned `moon` to run:

```text
moon run scripts/application-source.mbtx -- build <absolute consumer path> browser main release
moon run scripts/application-source.mbtx -- build <absolute consumer path> native main release
moon run scripts/application-source.mbtx -- build <absolute consumer path> native dev debug
```

The browser build creates both `app.mjs` and `app.wasm` in
`browser/.metonic-dist`. From the consumer root, run
`mise exec -- moon run package-browser.mbtx -- <new output directory>` to
assemble the page, runtime, notices and a SHA-256 inventory. Serve that output
over HTTP. WasmGC is the default; add `?target=js` to use the JS build.
After the native release build, run
`mise exec -- moon run package-native.mbtx -- <new output directory>` for the
executable, runtime assets, notices and inventory. Both packaging commands
refuse an existing destination. The native release entry does not import the
development controller. The separate `dev` entry can expose the documented
local CLI/MCP session when `METONIC_DEV_PIPE` is set.

Update Metonic by checking out a newer complete commit in
`.metonic/framework`, changing the one revision in `dependency.json` to that
same commit, and rebuilding both targets. The source entry rejects mismatched
or dirty framework checkouts. Format only this consumer's package paths, not
the generated dependency workspaces.

## What this first flow exposed

| Kind | Observed work |
| --- | --- |
| Application logic | Order identity, filter behavior, selected document and editable fields. |
| Framework-required code | Explicit `UiList.reconcile` after search, setting and title changes; manual control bounds and `Application` callback wiring. |
| Host boundary | Small native and browser entry packages, plus an HTML/module shell for the browser. Consumer packaging scripts still list runtime files and native notices explicitly. |
| Granularity gap | `Signal[Array[WorkOrder]]` replaces the whole array on one edit. This is a deliberate evaluation baseline, not the Phase 6 Store design. |

The Windows development CLI initially rejected snapshots with the standard
list and checkbox roles, then rejected list-item activation. The corresponding
framework fixes are [#645](https://github.com/dijdzv/metonic/issues/645) and
[#646](https://github.com/dijdzv/metonic/issues/646). With those fixes, CLI
activation of `WO-102` updated the title/details view, and a removed item's
old target returned `stale_target`. In headless Chromium, the same
select/edit/search flow worked on both JS and WasmGC, and both builds started
from a packaged browser directory. The packaged Windows executable also
started and closed through the normal close message and system-key path with
an unrelated working directory and no font override. Physical IME behavior
and durable save remain separate verification items.
