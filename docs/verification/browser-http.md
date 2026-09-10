# Browser HTTP ownership

`browser_host/app/http.mbt` owns fetch, AbortController, response content-type
validation, bounded byte collection, response decoding and application completion.
The shared browser application accepts request strings and response bytes directly;
the legacy numeric exports delegate to the same validation and state transitions.

Each request owns a live flag and its reader. Replacement, Cancel, Reset and Stop
invalidate it before aborting I/O. Every response callback checks that flag before
touching the application. Cleanup cancels the reader and releases its lock after
the cancellation promise settles. Late rejection cannot complete a new request.
Task-scope validation remains a second check when a result reaches shared state.

The response budget is 65536 bytes. A chunk exceeding the remaining budget is
rejected before its bytes are appended; the complete payload is decoded as strict
UTF-8. Empty bodies reach the ordinary invalid-JSON path. Content-type acceptance
and the three-second deadline match the previous transport.

Each MoonBit request owns its deadline timer through the existing webapi Window
and Function bindings. Common cleanup clears it on completion, cancellation,
replacement or disposal. Its callback captures the original request, whose live
flag rejects late completion; it never selects a replacement request from global
state. DOM result notification connects the transport to the existing renderer.
GPU calls, frame scheduling and module bootstrap remain separate host boundaries.

## Binding selection

The pinned webapi source is prepared with `webapi-http-boundary.patch` after the
existing callback-identity and warning patches. It exposes nullable Response.body
through a JsValue-to-Option conversion and adds Uint8Array length and bounds-checked
byte reads on JS/WasmGC. The source preparation compares an existing destination
instead of overwriting it; the runtime packaged with the app matches that source.

A generator correction for nullable attributes was evaluated separately with
regressions and regenerated browser execution. This adoption includes the Response
getter needed here; it does not change every nullable attribute's public API.
Other attribute consumers require their own migration. The typed-array extension
is a candidate for the existing binding library. No upstream publication is implied.

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
