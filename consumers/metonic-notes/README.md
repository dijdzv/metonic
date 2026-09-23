# Memo

A local application using Metonic's experimental application entry on Windows
native, browser JavaScript and browser WasmGC. This directory does not require
its own Git repository. It supports a collection of multiline memos with automatic
and explicit saving, discard, restoration and retry after storage failures. The packaging commands
below produce relocatable Windows and browser bundles with dependency notices.

This is a standalone source consumer stored in the Metonic repository for
reproducibility. Its `common`, `browser/app` and `native` modules remain separate
from the framework modules. Copy this directory elsewhere to work outside the
Metonic checkout; its `dependency.json` fetches the pinned framework revision.
Do not copy generated `.metonic`, `.metonic-build`, `.metonic-dist` or `moon.work`
contents when sharing the source.

## Saving

New memo creates and selects a memo. The list scrolls to additional memos;
`*` marks the selected memo. Move up and Move down change its order, including
the order restored after saving. Switching selection retains edits in
memory. Delete memo asks for a second confirmation; editing or selecting another
memo cancels that pending confirmation. Committed edits, creation and confirmed
deletion schedule a save after 500 ms without a newer change. IME preview does
not start a save. Save all bypasses the delay. A storage failure preserves the
draft and stops automatic retries; use Save all to retry explicitly.

Save all writes the entire collection. Discard all changes restores the last
loaded or saved collection, including created and deleted memos. With unsaved
changes, the native title-bar close button or browser Stop opens a close decision:
Save writes the collection and closes after success, Discard restores the saved
collection and closes, and Cancel returns to editing. A failed save leaves the
decision open for retry or cancellation. Closing during an existing save waits
for that save without starting another; Cancel prevents automatic closure when
it finishes. Closing during the debounce delay preserves the save/discard/cancel
decision instead of silently treating the draft as saved. Discard during that
delay cancels the pending save before restoring the saved content.
Browser navigation may show a confirmation, but forced termination cannot
be prevented.
During active Japanese composition, finish or cancel the conversion before
retrying Close/Stop; the editor remains available and the unfinished input is
not silently discarded.
Loading failure keeps editing and collection changes disabled; Retry load
retries without replacing stored data with an empty collection.
Each memo currently has a limit of 1024 UTF-16 code units.

Search filters memo contents after a short typing delay, ignoring case. Clearing
the search shows every memo again. Search does not change the selected memo or
cancel its pending save. The editor can therefore show a selected memo that does
not match the current filter. Edits, creation and deletion refresh the filtered
list; results from an older query or collection cannot replace the current list.

Native inputs support Ctrl+C, Ctrl+X and Ctrl+V. A clipboard failure appears
beside the save status and does not erase a storage error or delete text after
a failed cut. Retry the shortcut after resolving the failure; a successful
clipboard operation clears its input error. Browser inputs use the browser's
standard copy, cut and paste behavior. Clipboard operations during native IME
preedit are left to the IME until the composition ends.

Snapshots use a versioned application-owned format. Earlier plain-text snapshots
load as one memo and migrate when saved. Missing storage starts an empty list.
Malformed or unsupported snapshots fail loading. The `METONIC_NOTES` first-line
marker is reserved for the collection format; a legacy memo starting with that
exact line requires manual recovery rather than silently interpreting it as text.

Windows stores the snapshot under `%LOCALAPPDATA%/MetonicNotes`, or the directory
specified by `METONIC_NOTES_DATA`. An exclusive lock prevents a second cooperating
native instance from writing the same store. Browser storage uses the key
`metonic-notes.snapshot.v1` in localStorage for the current origin and browser
profile. Use one browser tab for editing: concurrent tabs are not coordinated
and the latest save wins. Changing the origin or port uses different storage;
private browsing and clearing site data can remove it. Native and browser data
are separate and are not synchronized or backed up automatically.

## Dependencies and setup

`dependency.json` pins the Metonic source revision. Clone that revision into
`.metonic/framework`; do not substitute a floating branch. The framework's
bootstrap pins its compiler. `metonic.application.json` names only this app's
workspaces, application members and entries. Each build calls Metonic's public
source entry, which verifies the pin and prepares the selected target's internal
dependencies before generating its workspace. A browser-only build does not
require native dependency preparation.

Windows requires mise, Git and the prerequisites listed in
[Metonic's development guide](.metonic/framework/docs/development.md), including
the Visual Studio C++ build tools and Rust for AccessKit preparation.

```text
mise trust
mise install
mise run deps:fetch
mise -C .metonic/framework trust
mise -C .metonic/framework run bootstrap
mise exec -- pnpm install --frozen-lockfile
```

The public source entry rejects a mismatched revision, tracked or non-ignored
untracked source changes, and an unpinned compiler. It generates only the
selected platform workspace after preparation. Keep the platform workspaces
separate; a workspace at the application root would also capture the framework's
own standalone tool builds. The generated `moon.work` files are owned by
Metonic; the app's member declarations live in `metonic.application.json`.

Keep this directory's `package.json` without `"type": "module"`; browser scripts
use `.mjs` explicitly. The pinned native GPU dependency has a CommonJS prebuild
script which can inherit the consumer's Node module scope. Declaring the whole
consumer as an ES module currently breaks that dependency's prebuild.

Update the pinned revision and dependency checkout together, then run the
platform and package verification commands below. The public build prepares its
selected dependencies. Do not edit registry packages or generated bindings by hand.

When copying the application to another directory, reinstall development
dependencies from the lockfile instead of copying `node_modules`: Windows pnpm
junctions can retain the previous absolute location. Build outputs and the paths
listed in `.gitignore` are generated state, not application source.

## Build and verification

```text
mise run build:browser
mise run build:native
mise run run:native
mise run verify:browser
mise run verify:native
mise run verify:persistence
mise run verify:model
mise run verify:source-contract
mise run verify:source-first-setup
```

The source-contract check covers mismatched and dirty framework checkouts,
missing bootstrap, and preservation of an application-owned workspace. The
first-setup check uses a disposable clean checkout, builds the browser JS and
WasmGC targets before any native preparation, updates the pinned revision,
rejects replacement of a handwritten workspace, and builds native from its
first preparation. It downloads the pinned toolchain into that disposable
checkout and can take several minutes.

Browser output is `browser/.metonic-dist`. Serve that directory over HTTP and use
`?target=js` or `?target=wasm-gc`. The browser verifier owns its HTTP server and
headless Chromium, checks both targets, and saves captures in
`verification-output`. Its JavaScript is confined to the Playwright/browser and
HTTP host boundary; application state and build orchestration use MoonBit.

`mise run package:browser <new-output-directory>` builds and copies the explicit
browser runtime/asset/notice inventory into a fresh distribution directory.
Existing destinations are rejected without overwriting them. `package.json`
records byte counts, SHA256 hashes and the framework revision; `DISTRIBUTION.md`
contains serving, storage and dependency notice information. Partial output after
an I/O failure has no completed manifest and must not be deployed.

`mise run verify:browser-package` builds, packages to an owned temporary Unicode
path, checks the inventory hashes and overwrite refusal, then serves that package
over real HTTP. It runs layout/editing and the full collection/persistence/retry
suite for JS and WasmGC from an unrelated working directory. It closes its own
headless browsers/server and removes its temporary output. This does not certify
Japanese physical IME input or arbitrary browser/platform compatibility.

The native release executable is
`native/.metonic-build/native/release/build/local/metonic_notes_native/main/main.exe`.
The build places `accesskit.dll` and `assets/NotoSansJP.ttf` with its OFL notice
beside the executable. `mise run run:native` and direct launches use those bundled
assets without a font environment variable or a particular working directory.
Keep the DLL and `assets/` directory with the executable when copying it. Use
`mise run package:native <new-output-directory>` to produce the explicit
distribution instead of copying the entire build directory. It includes the
framework/dependency notices, verifies the generated Rust notice inventory and
writes a file-hash manifest. Existing destinations are rejected. See the shipped
`DISTRIBUTION.md` for storage, graphics and Visual C++ x64 runtime prerequisites.
Clean-machine installation is not certified by the local relocation tests. The native
verifier owns a hidden window and checks editing, changed rendered pixels,
shutdown and disposed state using the same default resource lookup.
The collection places the list above the editor at small sizes and beside the
editor in larger windows. Layout and resize checks cover 320 × 360
through 1200 × 900 pixels. Browser CSS keeps a scrollable minimum canvas.
The native entry requests a 320 × 360 minimum client size. Resize verification
also requests 100 × 100 and checks that the actual client area stays at the
minimum without losing its memo text.

`mise run verify:native-package` builds production and separate test entries,
checks release exclusion against positive development controls, and packages to
an owned Unicode temporary path. An external MoonBit verifier starts the normal
packaged executable from an unrelated working directory with isolated storage.
It posts messages only to its owned application window to create/edit memos,
select and confirm deletion, save, close, restart and edit the restored memo.
This validates window-message routing and persistence, not physical pointer
movement or Japanese IME composition. The verifier is not included in the
distribution and no control endpoint is added to the release application.

These tests do not establish physical IME behavior. Browser input is capped at
1024 UTF-16 code units. The native editor can retain longer unsaved text, but
the memo model rejects saving it until it fits the document limit. Raster layer
size limits apply on both hosts.

`verify:model` checks schema migration, collection operations, save-snapshot
acknowledgement, invalid-store protection, dynamic row identity and layout bounds.
The compiled browser
verification exercises application operations on both targets.

`verify:persistence` owns a temporary storage directory and two hidden native
processes. It checks invalid stored data, retry after correcting that data,
write failure, retry, dirty-close refusal, collection creation/selection/deletion,
discard, shutdown and restoration of five Japanese multiline memos in a second
process. It does not use the normal user-data directory. Browser verification
also runs scrolling and reordering, legacy migration, empty collections, save/reload,
injected quota/access failures and retry on
both targets; fault injection does not establish physical quota exhaustion.

## Physical native input acceptance

Use a disposable memo in the ordinary native executable. These operations use
the real Windows clipboard; automated tests use injected or headless clipboard
implementations instead.

1. Enter and commit `あいうえおABC`. Drag across `いう`, press Ctrl+C, move to the
   end and press Ctrl+V. The result should be `あいうえおABCいう`.
2. Select the appended `いう` by dragging in the opposite direction. Ctrl+X
   should remove only that selection; Ctrl+V should restore it at the caret.
   Save, close and reopen to confirm the same memo is restored.
3. Start Japanese composition, click elsewhere in the input to finish the
   composition, then drag a new selection. The selection should follow the new
   gesture and stop extending after button release. Drag across several lines
   and outside the input to check that scrolling follows the selection.

Record the executable's framework revision and any failing step. This focused
acceptance complements window-message tests; it is not a request to repeat all
previous IME checks after every change.

## Native development control

`mise run build:native-dev` builds a separate debug entry with the public
application control adapter. Set `METONIC_DEV_PIPE` to a unique local pipe name
before `mise run run:native-dev`; stderr prints the discovery file path. Connect
using the pinned framework's `tools/devtools/application-mcp.mjs --session <path>`
or its `native_cli --session <path>` entry, following its application-entry guide.
The MCP adapter attaches to this app and does not launch it.

`mise run verify:native-control` owns a hidden development instance and isolated
storage. It uses the MCP SDK to create/edit/save a Japanese multiline memo,
capture its rendered result and reconnect, then checks the actual stored
snapshot. A direct pipe request with a stale session identity must reject a valid
targeted edit without changing controls or their revision. It then requests normal window closure, checks successful process exit
and verifies that discovery metadata is removed. Release shutdown and restart
are covered separately by `verify:native-package`. Neither is physical
IME verification. The release entry does not import the control adapter, and
the package inventory excludes the development executable.

## Browser development control

The framework's pinned Playwright provides both CLI and MCP attachment to an
existing development browser. No application-specific endpoint or global hook
is included in the browser bundle. Follow the framework's
`docs/application-entry.md` browser development control instructions to start a
dedicated browser/profile, attach through its loopback CDP endpoint and select
the memo application's exact URL before operating.

`mise run verify:browser-control` owns a headless Chromium profile and local
server. For both JS and WasmGC, it attaches the actual Playwright MCP server,
creates/edits/saves a memo, captures the canvas and reconnects. It then attaches
the actual Playwright CLI, edits/saves/detaches and reloads to check persistence.
Both disconnect paths must leave the app running. The check also runs as part
of `verify:browser`; SDK text insertion is not physical IME verification.

Keep the debugging browser isolated from ordinary personal browsing. Its CDP
endpoint controls the browser, and its profile/origin determine the memo data
visible there. The native revision-checked protocol and browser DOM automation
have different concurrency guarantees; avoid simultaneous editing clients.

## Ownership

`common/model` owns the application model. `native/main` and `browser/app/main`
only connect it to the shared hosts. Native verification is a separate entry in
`native/probe` and is absent from the ordinary application. Browser HTML and its
small shared-runtime configuration are in `browser`. Framework code, generated
WebSys bindings and platform internals remain inside the pinned dependency.
