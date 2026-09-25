# Phase 5 development diagnostics verification

The diagnostic implementation at `525ba6b` was checked on Windows 11 Pro
10.0.26200, Intel i5-13400, with the pinned MoonBit toolchain and Node 26.8.1.
These are local observations, not a performance guarantee.

`core/reactive_task` passed 43 JS and 43 native tests. The driver observer
passed 38 JS and 38 native tests. The controlled async-pair fixture passed in
browser JS and WasmGC, including pending, expected failure, retry, cancellation
and eventual cleanup join; native display and development CLI snapshot checks
passed. Tests separately cover capacity rejection, stale callbacks, unexpected
failure, disposal, ring overflow and diagnostic reads without reactive
subscriptions. The registry stores opaque key IDs and causal source identities,
not request values or error text.

The normal browser package and native release executable were built after the
change. The browser packager's fixed inventory and WasmGC string checks reject
diagnostic entry markers. A binary scan of the ordinary async-pair package,
browser release assets and native release executable found none of
`diagnostics_json`, `request_admitted`, `cleanup_joined`, `expected_failure` or
`unexpected_failure`. The dedicated development WasmGC module was 1,933,190
bytes versus 1,922,618 bytes for the ordinary async-pair module, an added
10,572 bytes in the development build; it is outside the release inventory.
The packaged P0 WasmGC module was 1,915,165 bytes, and the native release
executable was 13,725,184 bytes. Sizes are uncompressed local artifacts.

With diagnostics absent, the fixed synchronous Graph benchmark took
32/41/30 ms on native, 62/63/52 ms on JS and 12/11/12 ms on WasmGC for three
100,000-write runs. All checksums matched. Compare the
[pre-async baseline](reactive-phase4-baseline.md) of 36/34/34, 68/58/53 and 11/12/11 ms, and the
Phase 4 results in [async-pair verification](async-pair-phase4.md). The short,
integer-millisecond samples do not establish a material regression or
improvement.

The existing Notes 1,000-memo operation limits passed one warmup and three
measured runs each in browser JS, browser WasmGC and native. The native release
resource limits passed the same sample count. Detailed local measurements remain
under ignored `consumers/metonic-notes/.work/scale/`. For this comparison, the
consumer was temporarily pinned to `525ba6b` and given `downstreams: None`, a
new required Application field since its older pinned revision. Both temporary
changes were restored after measurement. Updating the consumer's public API
usage and revision is separate work; the test does not prove that the old
consumer builds unmodified against this commit.
