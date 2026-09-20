# Browser HTTP ownership

`browser_host/app/http.mbt` owns fetch, AbortController, response content-type
validation, bounded byte collection, response decoding and application completion.
The shared browser application accepts request strings and response bytes directly;
the legacy numeric exports delegate to the same validation and state transitions.

Each request owns a live flag and its reader. Replacement, Cancel, Reset and Stop
invalidate it before aborting I/O. Each resumed request checks that flag before
touching the application. Cleanup cancels the reader and releases its lock after
the cancellation promise settles. Late rejection cannot complete a new request.
Task-scope validation remains a second check when a result reaches shared state.

The response budget is 65536 bytes. A chunk exceeding the remaining budget is
rejected before its bytes are appended; the complete payload is decoded as strict
UTF-8. Empty bodies reach the ordinary invalid-JSON path. Content-type acceptance
and the three-second deadline match the previous transport.

Each MoonBit request owns its deadline timer through generated WebSys Window
bindings. Common cleanup clears it on completion, cancellation,
replacement or disposal. Its callback captures the original request, whose live
flag rejects late completion; it never selects a replacement request from global
state. DOM result notification connects the transport to the existing renderer.
GPU calls, frame scheduling and module bootstrap remain separate host boundaries.

## Binding selection

`browser_host/http.idl` supplies the WasmGC request, stream, abort and timer surface;
JS uses the matching upstream WebSys sources. Both come from the verified snapshot
prepared by `prepare-websys-input.mbtx`. Backend adapters normalize generated
descriptor and error representations; the request loop, budget and live-state
checks remain shared MoonBit code. Stream chunks are copied through WebSys's
checked `JsValue::to_bytes` conversion, preserving view bounds and ownership.

The request loop and reader cleanup use the browser workspace's pinned experimental
official-async candidate. Its hidden `run_async_main` integration entry starts the request and cleanup
coroutines; WebSys Promise adapters resume them. This does not replace the existing
application task scope or move animation/input scheduling into an independent
scheduler. WasmGC support remains dependent on the reviewed async patch described
in the [dependency record](dependencies.md). This is a pinned integration boundary,
not a stable public async API: the candidate does not yet provide a working
WasmGC `Promise::from_async` entry. Upstream entry-point compatibility must be
checked when updating the candidate.

The JS timer adapter only converts the compiled callback to WebSys's opaque
Function type. Fetch, stream operations, timer registration and DOM notification
all use generated APIs. Font fetching, task timers and control placement also use
WebSys; the browser workspace no longer imports bikallem/webapi.

## Verification

Run `mise run browser:headless` to exercise the packaged UI against the owned HTTP
fixture, including domain/protocol errors, invalid content/JSON, the exact byte
limit, oversized responses, disconnect, timeout and a stalled response body.
The same flow checks recovery, replacement/cancellation and Stop with a pending
request. See [UI HTTP failures](ui-rpc-failures.md) for its external-server contract.

The browser package tests run on JS and WasmGC and check direct Japanese and
supplementary-character payloads, malformed UTF-8, excessive length and obsolete
response rejection. API/binding checks do not establish real Japanese IME behavior
or arbitrary network timing. Physical input acceptance remains separate.
