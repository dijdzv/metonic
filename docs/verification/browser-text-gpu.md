# Browser text GPU boundary

`browser_host/app/text_gpu.mbt` owns the text shader, pipeline, textures,
uniform buffers and bind groups on JS and WasmGC. Layers are uploaded into a
pending batch. A complete batch replaces the previous resources; a JavaScript
exception aborts the pending resources. Disposal releases pending and committed
textures/buffers and drops references to the remaining GPU objects.

The JavaScript text host retains font digest verification, conversion of the
MoonBit byte representation to Uint8Array, Float32Array construction for uniform
data, and the boundary that catches synchronous browser exceptions. Device and
canvas setup, frame submission and scheduling remain in the host. GPU migration does not
claim that all browser JavaScript has been removed.

`browser_host/app/scene_gpu.mbt` owns the scene pipeline, uniform buffer, bind
group and draw recording. Initialization retains the asynchronous WebGPU
pipeline API. Disposing or replacing a pending initialization invalidates its
callback before it can allocate buffers; a partially created buffer remains
owned until the host's error cleanup calls disposal. Repeated disposal is safe.
The headless suite checks this lifetime contract on JS and WasmGC separately
from the real GPU pixel, resize, movement and stop scenarios.

## Dependency preparation

`mise run browser:build` runs `scripts/prepare-browser-gpu.mbtx`. It verifies the
webapi archive at `ecae5a4b07b011e46de343efe2ac1c450b7ed3a2` with SHA256 and
`@webref/idl` 3.73.1 with SHA512 before extraction. The script applies
`patches/webapi-webgpu-generator.patch` and the specification selection in
`scripts/webgpu-generator.json`. Generated files remain under
`.work/browser-gpu/generated`; releases include the matching runtime and license.

The local generator correction retains type attributes, resolves numeric aliases,
converts the exercised UInt64/attribute ABI, and selects a GPUCanvasContext
fallback only when the interface is absent. It also preserves Metonic's existing
nullable HTTP body, Uint8Array access and callback identity corrections. The
patch is an upstream correction candidate, not an upstream release or a claim
of complete WebIDL support. Signed integer/bigint distinctions, nullable numeric
aliases and all method/promise conversions are not comprehensively verified.

Generated dependency warnings 20, 35, 53 and 83 are suppressed for the pinned
upstream syntax/API; application packages continue to build with `--deny-warn`.

## Verification and limits

Run `mise run browser:headless` for the normal JS/WasmGC and release paths,
including text pixel comparison, input, HTTP failures and disposal scenarios.
The bulk-transfer comparison still checks every byte against the scalar export
before uploading through the MoonBit GPU boundary.

During dependency evaluation, seven application-produced layers and normal/moved
640×480 compositions matched the existing renderer on both targets. Normal and
injected bind-group failure paths released all tracked buffers/textures. These
local experiments establish API calls and pixel equality, not driver memory
reclamation or independent text-shaping correctness. The assembled generator's
221 package tests passed; the upstream `make all` workflow was not run.

The renderer still replaces all layers when the shared raster result changes.
Stable layer reuse, retained shaping and device-loss recovery are separate work.
Synthetic input and GPU readback do not establish physical IME or assistive
technology acceptance.
