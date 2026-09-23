# Independent memo application operations

The [independent consumer source](../../consumers/metonic-notes/README.md),
`metonic-notes`, exercises the public application entry from separate MoonBit
modules. The operational checks below were recorded against framework revision
`8ee85dba6899341e040531de274e2c5761e819a1`; the consumer's
`dependency.json` selects its current pinned revision.
It is separate from the repository's in-memory Notes example and is not a
published package. The commands below run from that consumer's root; they are
not framework tasks. The historical raw results remain local. The source is
now checked in; the setup and builds at the newer pinned revision are recorded
below rather than attributed to those older operational runs.

## Application behavior

Committed memo edits, creation and confirmed deletion schedule a save after
500 ms. Save All starts immediately. A stable save operation serializes writes
through the public task driver. Search has its own operation and 100 ms delay;
replacing a query does not cancel a save. One production `SystemClock` supplies
both waits. Environment-independent models receive an injected wait function.

Search matches memo contents case-insensitively. Clearing the query restores
the complete list. Filtering does not change the selected editor. Query and
document generations reject stale results, including results computed before
an edit or deletion. Collection changes also refresh the current filter.

A save acknowledges only its captured snapshot. The application records a
completed storage result before UI delivery; replacement preparation reconciles
that result after the driver has joined previous cleanup. This prevents a
completed write from being forgotten when its UI completion is superseded.
Newer edits remain dirty. Failure suspends automatic retry, including a queued
save whose preceding write failed; Save All explicitly retries.

Close during the delay still offers save/discard/cancel. Discard cancels and
joins pending save work before restoring the acknowledged snapshot. A write
that has already started retains the existing close/wait policy. IME preview
and selection movement do not themselves schedule saves.

## Verification

| Consumer command | Evidence and scope |
| --- | --- |
| `mise run verify:model` | 36 JS and 17 WasmGC tests passed after the shared list migration. Async model cases run on JS. Controlled waits cover search/save coexistence, stale results, save receipts, failure before replacement preparation, discard/close during debounce and explicit retry. |
| `mise run verify:browser` | Browser JS/WasmGC editing, collection operations, storage recovery, CLI/MCP, autosave and search passed. This combined run preceded the final filter refresh on committed edits; the later package check exercises that revision. |
| `mise run verify:browser-package` | Both backends passed from a relocated Unicode path and unrelated working directory. File inventory/hash and overwrite protection checks accompany editing, collection persistence/recovery, autosave reload and search/save coexistence. The run took 40.25 seconds. |
| `mise run verify:native` | The owned-window probe passed search filtering/clearing while a distinct edit was saved, then saving a later close draft and cleanup. |
| `mise run verify:native-control` | CLI/MCP editing, save requests, rendering, disconnect/reconnect and actual snapshots passed against isolated real storage. |
| `mise run verify:native-package` | Copied Windows release passed forward/backward drag replacement, saving, restart/restore and exit from a Unicode path and unrelated working directory. Inventory/hash, overwrite protection and development-code/link exclusion checks passed. |
| `mise run verify:source-contract` | At the final pinned revision, rejected a mismatched or dirty checkout and missing bootstrap without replacing a handwritten workspace. |
| `mise run verify:source-first-setup` | From a disposable clean checkout, bootstrapped the pinned compiler, built JS and WasmGC before native preparation, updated the source revision and rebuilt, refused to replace a handwritten workspace, then prepared and built Windows native. |

The browser package check runs the same autosave/search assertions against the
copied distribution rather than a development build path. Native semantic
operations exercise the actual application and task driver but do not simulate
physical keyboard or IME events. These results do not establish new physical
IME acceptance, clean-machine installation, concurrent multi-process editing,
or power-loss durability.

The native release probe's editor coordinates were updated when the search row
moved the editor. It posts messages only to its owned process window. Its
replacement assertions remain intact; this is automated message-path evidence,
not physical mouse or OS IME acceptance.

The consumer now uses the shared list layout for scrolling, reordering and
focus reveal instead of application-owned four-row pagination. Its target
manifest supplies application members; the Metonic source entry owns internal
dependency preparation and workspace generation. The final source setup and
revision-update checks above establish that path for this local consumer, but
the historical raw results remain local. The consumer source can now be copied
from this repository and prepared independently.

## Reproducible source check at the current pin

At framework revision `2be1ddcbcb4e5e944b311d809322910d67e3fc6b`, the
checked-in consumer fetched the exact source revision and bootstrapped its
pinned MoonBit compiler without reusing the earlier local consumer's dependency
checkout. `mise run build:browser` built both JS and WasmGC; `mise run
build:native` built the Windows application. `mise run verify:source-contract`
rejected a wrong revision, a dirty dependency checkout and a missing bootstrap
without replacing a handwritten workspace. `mise run verify:source-first-setup`
created a separate clean consumer under a path containing a space, bootstrapped
the dependency there, built JS/WasmGC before native preparation, changed to a
new pinned source revision and rebuilt, then prepared and built Windows native.
These checks establish source preparation and builds, not a fresh repetition of
the historical autosave, search, physical IME or package-operation evidence.
