# Native Rust dependency notices

From the prepared framework checkout, run the pinned Moon executable through
mise with `run scripts/prepare-native-rust-notices.mbtx`. This requires the
existing Rust/Cargo, curl and tar prerequisites and network access on first use.
The result is `.work/native-rust-notices/distribution`.
`inventory.json` records output hashes and the source lockfile/configuration
hashes. It is invalidated before preparation and written last; a failed run must
not be consumed as a complete notice set.

This preparation uses cargo-about 0.9.2 rather than implementing license detection
or SPDX expression handling. Its Windows binary archive and the wgpu-native
source archive are SHA256-pinned. wgpu-native source corresponds to the existing
v29.0.1.1 binary release, commit
`6aed50955d934ac36049ba8d002034841633ae02`. AccessKit is resolved from the actual
prepared and patched 0.22.3 source. Cargo uses `--locked`; dependency sources are
not rewritten to add missing notices. The default-feature Windows graph includes
build-time dependencies conservatively, so it is not a list of required runtime
DLLs. Tool and raw report files remain outside the distribution directory.

The configurations prefer MIT when a package offers MIT OR Apache-2.0. Explicit
clarifications retain the upstream license expressions and bind the selected
text to a SHA256. They address absent AccessKit/gpu-descriptor/profiling crate
notices, lower-case Windows license files and libm's combined license document.
AccessKit's local patched crates use a separately downloaded, pinned upstream
notice because cargo-about treats their source as local even with a Git commit
override. The registry AccessKit crate uses its pinned Git source directly.

Generation rejects tool diagnostics as well as known placeholder copyright
templates: a zero exit code alone can hide a failed clarification and synthesized
text. The separate AccessKit Chromium notice is included verbatim because it is
not represented by the top-level MIT OR Apache expression. libm's full combined
notice is retained, including its upstream attributions.

These files cover the Rust dependency preparation only. The final application
package must also include the applicable MoonBit module/core notices, font OFL,
framework/app licenses and any additional native library notices. This command
does not certify that an arbitrary application dependency graph is covered.

When updating dependencies, review the actual graphs and source notices before
changing hashes or clarifications. Do not silence warnings or accept a generated
placeholder to make packaging pass. Configuration behavior is documented in the
[cargo-about manual](https://embarkstudios.github.io/cargo-about/cli/generate/config.html).
