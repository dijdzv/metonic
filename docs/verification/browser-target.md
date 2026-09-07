# P0 browser backend selection

Recorded 2026-09-08 against the integrated application at `4c43490` with the
pinned toolchain. This supersedes the small rectangle-only artifact comparison
as the basis for selecting the P0 application backend.

| Observation | JS | WasmGC |
| --- | ---: | ---: |
| Uncompressed application artifact | 5,665,653 bytes | 1,822,759 bytes |
| Common staged host/font/license assets | 9,622,506 bytes | 9,622,506 bytes |
| Application plus common assets | 15,288,159 bytes | 11,445,265 bytes |
| Five-frame scene uniform uploads | 160 bytes | 160 bytes |
| Chromium physical GPU and SwiftShader checks | pass | pass |

The common-assets measurement includes the diagnostic HTML, host/loader/text
renderer, CSS, full Noto Sans JP font and license. It excludes the other target's
application artifact. These are uncompressed file sizes, not compressed network
transfer measurements or a finished distribution size. WasmGC saves about
3.84 MB for this application; the shared font still dominates total assets.

The verified browser was Chrome for Testing 153.0.8010.12. Physical adapter
metadata reported NVIDIA/Ampere, non-fallback; the software path reported
Google/SwiftShader, fallback. Both pass scene input/resize/idle/stop, shared text
pixels, staged editor composition, HTTP success/domain errors and cancellation
checks. These are the existing suite's coverage, not evidence of every RPC
failure case, physical IME or OS accessibility.

Single load observations were 81.8/19.2 ms on the physical path and 79.4/19.2 ms
on SwiftShader for JS/WasmGC respectively. They are **not benchmarks**: the loader
times different import/instantiation paths, excludes fetch time from its timer,
and does not measure full font/GPU initialization. They do not establish an
execution-speed advantage and are not the reason for the selection.

## Decision and distribution boundary

WasmGC is the P0 default because the integrated behavior passes the same tests
with a smaller application artifact and the existing shared host. JS remains
available with `?target=js` for comparison. There is no automatic backend fallback
and no claim about untested browser engines. See [ADR 024](../adr/024-browser-gpu-probe.md).

`.work/browser-dist` remains the comparison distribution with both targets and
`metonicAsyncProbe`. `mise run browser:package` produces the separate
`.work/browser-release` directory and `.work/metonic-browser-p0.zip` using a fixed
12-file list. It includes the WasmGC application, shared UI/text host, release
loader/environment, CSS, font, font license and project licenses. It omits the JS
application, comparison page and development environment module.

The UI loop, editor, GPU and HTTP behavior stay in the same host. Build-selected
`environment.mjs` supplies diagnostic DOM updates and the control global only in
the development distribution; the release environment supplies human-readable
task status and no-op hooks. Shared counters and hook call sites remain internal
implementation details. This is adapter exclusion, not a claim that every
internal metric or every public MoonBit export was eliminated.

The package tool rejects unexpected destination files, checks shipped text files
for development entry points, checks the development adapter as a positive
control, and verifies the archive member list. It does not silently delete files
from an existing destination directory.

## Run the packaged application

Use `mise run browser:release-serve` and open
`http://127.0.0.1:4173/release/`, or run `mise run demo` for the packaged browser UI
and native release window sharing one API. The existing local server serves the
package under that prefix, with a fixed allowlist. It also serves the separate
development comparison at `/`; that server is a verification/development tool,
not part of the browser ZIP.

To host the ZIP elsewhere, extract its contents into one directory, serve it over
HTTPS with `application/wasm` for the Wasm file, and provide the standard
same-origin `POST /rpc` API. Host and font URLs are relative to the page; the RPC
URL is origin-rooted. No backend or credentials are embedded in the archive.

## Packaged-UI verification

The normal `browser:headless` suite also drives `/release/` through ordinary DOM
controls and screenshots, without a development global. MoonBit owns the sequence
and assertions. It checks changed text pixels, preserved editor text and added
HTTP result pixels, domain errors, cancellation, resize, clearing the editor,
disabled input after stop and an unchanged frame after late input/timer work.
It also checks absence of the global and rejects requests for comparison assets.

Screenshots use the actual canvas. The pinned Noto Sans JP font covers the tested
Japanese/Latin text; the supplementary-character case does not establish emoji
glyph coverage. Physical IME, full accessibility and device loss remain separate
requirements. Additional [HTTP failure verification](ui-rpc-failures.md) covers
real loopback failures, recovery and cancellation on this package. Package
exclusion does not complete the remaining unverified requirements.

## Reproduction

Run `mise run browser:headless` with `METONIC_GPU_BACKEND=default`, then with
`METONIC_GPU_BACKEND=swiftshader`, using the pinned setup. Run
`mise run browser:comparison-report` after both complete. The MoonBit script reads
their results and current staged files and writes `.work/browser-comparison.json`.
It rejects target duplication, page errors and artifact-size mismatches.

Size equality is not a source-revision attestation: rerun the headless checks
when application or host behavior changes. The recorded revision is the checkout
at report time, not a claim that an arbitrary old result came from that revision.
Raw measurements remain ignored local artifacts.
