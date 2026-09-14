# Browser font integrity bindings

Apply `webapi-font-integrity.patch` after `webapi-webgpu-generator.patch` to
`bikallem/webapi` revision `ecae5a4b07b011e46de343efe2ac1c450b7ed3a2`.
The upstream HEAD was checked against that revision on 2026-09-14.

The patch supplies the missing `FromJsAny` implementation for optional Byte
values in generated Web Crypto dictionaries, and a typed ArrayBuffer constructor
for the existing Uint8Array binding. `from_buffer` is a shared view of the whole
buffer, matching `new Uint8Array(buffer)`; it neither copies nor transfers it.
Detached-buffer constructor errors remain browser errors. The application uses
a fresh, non-detached Web Crypto result and reads its 32 bytes synchronously.

The Byte correction was isolated for an upstream proposal in
[#218](https://github.com/dijdzv/metonic/issues/218). The constructor is a reusable
typed-array API gap, rather than font-specific logic. This local patch is not an
accepted upstream release. Its scope excludes enum-array conversion, general
cryptographic key management and a replacement Promise scheduler.

`scripts/prepare-browser-gpu.mbtx` applies the patch before generation. The
application retains the existing browser Web Crypto implementation; hash
comparison and request lifetime are in `browser_host/app/font.mbt`.
Run `mise run browser:headless` for both application targets, including corrupt
font rejection and stopping while digest completion is held.
