# ADR 032: Compose bounded HTTP with a clock

## Status

Proposed; integration acceptance is tracked in [Issue 429](https://github.com/dijdzv/metonic/issues/429).

## Boundary

`effects/http` defines a bounded POST exchange without a scheduler, UI types,
RPC envelopes or a global runtime. A request carries owned bytes, a relative
path, content type, response byte limit and acceptable response content types.
An empty acceptance list permits any content type. Adapters reject an unacceptable
type before consuming the body and enforce the byte limit during consumption.
This is a deliberately small HTTP capability, not a complete HTTP client API.

`examples/p0/user_load` owns the user request, JSON/domain decoding and visible
error mapping. The same operation receives native, WebSys or controlled HTTP.
Native and browser adapters own connections, AbortController and stream readers.
Cancellation propagates through async rather than becoming a transport failure.
The official JS Promise waiter protects a wait from cancellation unless its
AbortController argument is supplied. Both Fetch and reader waits therefore use
the transport's existing controller; creating another controller would not abort
the active Fetch. WasmGC waits supply the corresponding abort callback. A typed
JS identity bridge connects the two libraries' representations of the same host
controller without copying its state or reproducing compiler value layouts.

`async_runtime/http/TimedHttp` composes a transport and `Clock`. An official
structured task group races completion against sleep, cancels the loser and
waits for child termination. Zero duration expires without starting a request;
negative duration is rejected. When response and deadline are ready together,
scheduler order decides the winner; no cross-platform tie ordering is promised.
No independent scheduler, central Effect enum or application-model rewrite is
introduced. Task IDs continue to reject obsolete results independently of
transport cancellation.

## Verification and limits

Controlled responses and virtual time test success/errors, deadline cleanup,
outer cancellation, reversed replies and results arriving after replacement,
cancellation or disposal. They run on JS and native through pre-commit. Native
loopback tests additionally exercise headers, JSON/domain results and the 64 KiB
response boundary. Browser integration exercises production JS/WasmGC adapters;
it does not establish execution of the virtual-time suite on WasmGC.

The browser currently schedules reader cancellation/release in a separate async
cleanup operation after aborting Fetch. Returning from a request therefore does
not itself prove that the reader cancellation Promise has settled. Integration
checks use an actual pending ReadableStream to verify Abort, cancellation and
reader-lock release after explicit cancellation and deadline expiration on both
backends. Native integration advances virtual time while a loopback server holds
the response body open and verifies that the server observes connection closure.

General streaming application APIs, other HTTP methods, retries and full
record/replay remain outside this decision.
