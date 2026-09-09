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

Font fetch and Web Crypto hashing remain JavaScript browser boundaries. A
generated Web Crypto binding was separately prototyped and tested under issue
#216, but is not an application dependency. This change does not add streaming
limits before fetch collection, abort a pending fetch, or complete font-loading
lifecycle migration. Those requirements remain on #216; physical IME acceptance
is unrelated to these synthetic and headless checks.
