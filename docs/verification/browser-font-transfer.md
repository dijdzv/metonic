# Browser font transfer

The JS application receives a copied Uint8Array in one `font_receive` call after
the host verifies the pinned SHA-256 and checks disposal. The MoonBit receiver
clears prior pending input, rejects empty or larger-than-16-MiB input, and uses
the same font parser/commit path as the word receiver. The host must pass an
owned copy. The loader requires this export for the JS artifact.

WasmGC retains `font_begin`/`font_put`/`font_commit`. Its GC array representation
is not the JavaScript TypedArray ABI. A measured binary-string conversion was
slower, so it is not used for inbound font data.

## Evidence and limits

On 2026-09-09, an isolated Chromium 153.0.8010.12 comparison transferred the
9,589,900-byte packaged Noto Sans JP font, plus zero-, one- and three-byte inputs.
With three warmups and ten samples, JS copied-array transfer measured about
1.6 ms versus 22 ms for a simplified word receiver. WasmGC word transfer measured
42.4 ms versus 49.6 ms for binary-string conversion. All final received bytes
were compared; mutating the JS source left the received copy unchanged.

Those measurements include host conversion and allocation but exclude font
parsing, fetch and digest; the simplified word receiver omits application guards.
They are not integrated startup-time claims. The real application still copies
the fixed array into the parser's Bytes representation during commit.

Run `mise run browser:headless` for actual-font rendering, JS/WasmGC text output,
font fetch failure, wrong digest, delayed stop and packaged UI regression checks.
The browser MoonBit tests check empty, invalid and oversized bulk input, and
that rejected replacement clears pending word input. Both targets passed 14
package tests with the transfer change.

Font fetching now uses the MoonBit browser host and the existing Fetch bindings.
The loader checks the cumulative 16-MiB bound before retaining each stream chunk.
Stopping the host aborts the request, cancels an active reader and releases its
lock. The response is assembled through the browser Blob API; the bound limits
retained payload bytes, not total browser memory or transient assembly copies.

Web Crypto hashing remains a JavaScript browser boundary. The generated binding
prototype requires upstream generator corrections tracked in #218 and is not an
application dependency. Hash completion after disposal is ignored; this does not
cancel Web Crypto computation itself.

The headless suite exercises HTTP 503, wrong digest, a 16-MiB-plus-one-byte
response, stop before headers, stop while a controlled ReadableStream waits for
more body data, and stop before a held digest result returns, on both targets.
The stream fixture verifies one abort, one cancel and an unlocked reader. It
does not establish server-side disconnect behavior. All failure/stop scenarios
require zero submitted frames and no uncaught page errors. A loader-level test
delivers an obsolete response after replacement, checks that both promises reject
when cancelled, verifies that old cleanup preserves cancellation of the current
reader, and loads the actual font again. This exercises one module instance; it
does not add restart support to the stopped UI. Physical IME acceptance is
unrelated to these synthetic and headless checks.
