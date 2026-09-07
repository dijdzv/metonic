# Browser GPU verification

Recorded: 2026-09-06. Scope: P0-B rectangle and host boundary, not a UI framework.

## Reproduction

Use the pinned environment in [environment.md](environment.md), then:

```powershell
mise exec -- pnpm install --frozen-lockfile
mise run browser:install
mise run browser:verify
mise run browser:server-test
mise run browser:headless
$env:METONIC_GPU_BACKEND = 'swiftshader'
mise run browser:headless
Remove-Item Env:METONIC_GPU_BACKEND
```

The headless command launches its own loopback server and Chromium, records
screenshots/results under `.work/browser-headless/<backend>`, and closes both
processes. It uses browser automation APIs, not desktop input automation.

## Observed results

Chrome for Testing 153.0.8010.12 with Playwright 1.63.0 and Node 26.8.1:

| Check | JS output | WasmGC output |
| --- | --- | --- |
| Release artifact, uncompressed | 3,941 bytes | 1,047 bytes |
| Exported state transition and reset checks in Node | pass | pass |
| Headless physical GPU: NVIDIA / Ampere, non-fallback | pass | pass |
| Headless software GPU: Google / SwiftShader, fallback | pass | pass |
| Initial rectangle pixels | 120 × 72, teal | 120 × 72, teal |
| Pointer activation pixels | orange, unchanged bounds | orange, unchanged bounds |
| ArrowRight pixels | 10 px right | 10 px right |
| Viewport resize and in-bounds rectangle | pass | pass |
| Idle observation, 250 ms | no additional submissions | no additional submissions |
| Reset | original size/color | original size/color |
| Stop, then input and resize | no state or submission changes | no state or submission changes |
| Resource HTTP 503 | visible error, zero frames | visible error, zero frames |

An invalid target is rejected without drawing. Holding the Wasm response,
stopping the host, then completing that response leaves the host stopped with
zero submissions. This tests initialization disposal rather than only shutdown
after successful startup. No page errors occurred during the successful paths.

Each submitted frame uploads one 32-byte uniform buffer. The five-frame sequence
uploads 160 bytes; idle periods upload none. This excludes browser-internal GPU
copies. Field reads are scalar calls into MoonBit, not a batched scene ABI.

The shared scene tests also passed on native/MSVC, JS, and WasmGC: five new
state tests plus the existing RPC test per target. Existing compile-fail contract
fixtures continued to pass.

The server tests verified GET/HEAD and MIME handling, rejected POST, and rejected
unlisted files and path traversal attempts. It binds only to 127.0.0.1 and serves
an explicit asset list.

## Artifact verifier ownership

`tools/verify_browser_artifacts` contains the MoonBit verification sequence:
five required function exports, eight complete snapshots per target, mutation
return values, reset and equality between the JS and WasmGC histories.
`scripts/verify-browser.mjs` only imports the actual release artifacts,
instantiates WasmGC with the existing host imports and calls that verifier.
The verifier's small JS FFI functions access the exported API; application state
and expected results remain in MoonBit.

The exported verification entry point converts validation failures to JavaScript
exceptions so Node exits unsuccessfully. A MoonBit error result returned across
the foreign-library boundary must not be silently treated as successful execution.
Four whitebox tests passed on the JS target: missing export, incorrect initial
state, incorrect mutation result and JavaScript exception propagation. Run them
with `moon test tools/verify_browser_artifacts --target js --frozen --deny-warn`
using the pinned toolchain; the normal local verification gate includes them.
This check exercises generated artifacts in Node, separately from the real
WebGPU pixel and input checks above.

## Headless pixel verifier ownership

`tools/verify_browser_pixels` decodes screenshots with the existing MoonBit
`mizchi/image` dependency. It owns rectangle color thresholds, bounds and movement
tolerances, text crop extraction and byte comparisons, blank-text checks, and
the exact nearest-neighbor DPR-2 comparison. The host passes screenshot bytes as
base64 and receives a JSON result. Only an explicit `ok: true` is accepted by the
JavaScript adapter; parsing or validation failures fail the browser check.

Cropping uses the text width capped at 640 pixels, an origin of (8, 8), and 96
rows. Crop bounds are checked before reading pixels. The DPR-2 reference is a
640-by-96 RGBA crop and is compared against the doubled region starting at
(16, 16), including every alpha channel. These are screenshot comparison rules,
not an additional rendering implementation.

Playwright operations, browser/page lifetime, state polling, resource-failure
scenarios and result-file writing remain in `scripts/verify-browser-headless.mjs`.
Moving the pixel checks does not establish that all browser verification is
implemented in MoonBit. `mise run browser:headless` builds and tests the pixel
verifier before starting the browser supervisor.

On 2026-09-07, seven pixel-verifier tests passed, covering success and rejection
for scene movement, crop bounds, text equality expectations, blank alpha/RGB
changes and DPR comparisons. A patterned DPR-2 image passed and a single-channel
mutation in its comparison region failed. The exported result rejects malformed
JSON and PNG input. Both default and SwiftShader headless runs passed for the JS
and WasmGC applications with their existing state and resource-failure checks.
The now-unused `pngjs` npm dependency was removed.

## Limits and next gate

The harness reports initialization timing for diagnostics. It is a single small
module, with different import/fetch paths and cache behavior; timings are not a
performance comparison. Artifact sizes exclude the common host and browser.
Both targets remain supported by the experiment; text and asynchronous bridge
work must inform a production backend choice.

Screenshots are captured by the headless browser and inspected as PNG pixels.
Fractional CSS clipping can add one border pixel to screenshot dimensions at DPR
1; rectangle position/size checks account for that. Submission is not a presented
frame acknowledgment suitable for the eventual development control protocol.

This does not validate native GPU rendering, OS window events, Japanese IME,
text shaping, accessibility, device-loss recovery, or production exclusion of
CLI/MCP. The host is an explicitly named prototype; no MCP server is shipped.
See [ADR 024](../adr/024-browser-gpu-probe.md) for the comparison boundary.
