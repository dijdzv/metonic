# Browser font transfer

The JS application receives a copied Uint8Array in one `font_receive` call after
the MoonBit request verifies the pinned SHA-256 and the host checks disposal. The MoonBit receiver
clears prior pending input, rejects empty or larger-than-16-MiB input, and uses
the same font parser/commit path as the word receiver. The host must pass an
owned copy. The loader requires this export for the JS artifact.

WasmGC retains `font_begin`/`font_put`/`font_commit`. Its GC array representation
is not the JavaScript TypedArray ABI. A measured binary-string conversion was
slower, so it is not used for inbound font data.

The word packing loop is implemented in `tools/browser_buffer` and compiled to
the shared JS host module. It sends little-endian words, zero-pads the final
partial word, and stops immediately on receiver rejection. Empty or larger-than-
16-MiB input is rejected before callback delivery. Fetch, digest completion and
disposal checks still precede the transfer; the JS bulk receiver is unchanged.

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

On 2026-09-13, the generated MoonBit loop and the handwritten loop were compared
against the application's actual WasmGC `font_put` receiver. With three warmups,
ten samples and alternating execution order, the 9,589,900-byte transfer medians
were 28.5 ms and 28.0 ms respectively. Parsing each result produced identical
475,648-byte raster layers. Timing excludes parsing and rendering, and does not
claim a speed improvement or a stable performance bound. Separate fixtures check
odd byte counts, all byte values and early rejection; package tests cover bounds
and tail padding.

Run `mise run browser:headless` for actual-font rendering, JS/WasmGC text output,
font fetch failure, wrong digest, delayed stop and packaged UI regression checks.
The browser MoonBit tests check empty, invalid and oversized bulk input, and
that rejected replacement clears pending word input. Both targets passed 14
package tests with the transfer change.

Font fetching uses the MoonBit browser host and generated WebSys Fetch bindings.
The loader checks the cumulative 16-MiB bound before retaining each stream chunk.
Stopping the host aborts the request, cancels an active reader and releases its
lock. Owned stream bytes are assembled in a MoonBit Buffer; the bound limits
retained payload bytes, not total browser memory or transient assembly copies.

The MoonBit request calls browser Web Crypto through the generated binding and
compares all 32 digest bytes with the pinned hash before returning the buffer.
Its lifetime extends through digest completion: cancellation rejects the late
result before font transfer or parser mutation. This does not cancel Web Crypto
computation itself. The host retains byte transfer and its disposal guard.

The WebSys surface in `browser_host/http.idl` includes WebCrypto digest and buffer
Promise results. `ArrayBuffer::from_bytes` and `to_bytes` copy across the host
boundary without sharing mutable storage. Digest comparison and cancellation
policy remain MoonBit. JS uses the official async Promise entry; the experimental
WasmGC backend uses a small host Promise-settlement adapter because that entry is
not implemented in the pinned candidate. Neither adapter performs HTTP or hash
validation in host code.

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
