# ADR 022: Development workflow and toolchain

Date: 2026-09-06 · Status: accepted

## Context

The project needs small reviewable changes, reproducible technical experiments,
and a low-overhead release process during early development.

## Decision

Use main as the integration branch, short-lived branches, squash-merged PRs and
version tags for releases. The current Git, local pre-commit and manual-CI rules
are maintained in the [development guide](../development.md#work-and-release-flow).
The earlier required `Windows verification` PR check has been retired; do not
interpret the original ADR as requiring duplicate automated PR validation.

Use mise as the command entry point and to pin Node for generated-JS verification.
Pin MoonBit archives and their hashes in `toolchain.json`; install them into
`.tools/moonbit`. The bootstrap builds the matching standard library and preserves
a previous local installation when replacing it.

The current baseline is MoonBit 0.10.11 from the non-dev distribution. Version
updates must recheck official distribution metadata, update the pin, and rerun
verification. Do not use a floating latest download in CI.

Node 26.8.1 is a test runtime; pnpm 12.3.4 manages locked browser-verification
dependencies. Bun is not required by the current
workload. Native product builds do not depend on these development tools.

## Alternatives

- Git Flow adds long-lived branches without a current maintenance need.
- A global MoonBit install can silently differ between development environments.
- A third-party installer plugin adds a dependency while official fixed archives are available.
- Automatic latest-on-every-build updates make compiler regressions hard to reproduce.

### Windows installer boundary review

The installed mise 2026.8.5 registry has no `moonbit` shorthand. This does not
rule out a custom backend: the [HTTP backend](https://mise.jdx.dev/dev-tools/backends/http.html)
supports fixed archive URLs and checksums. It can acquire compiler and core
archives, but acquisition alone does not assemble core under the compiler's
`lib` directory, bundle it, verify the pair and switch the project-local install.
Those steps would still need orchestration. A new installer plugin would move
that boundary to another implementation language rather than remove it.

The [official Windows installer](https://cli.moonbitlang.com/install/powershell.ps1)
accepts an explicit version and installs/bundles core, but the reviewed script
does not verify this project's two pinned hashes or retain the previous install
before overwriting it. It is not an equivalent replacement for this contract.

Use mise's HTTP backend for compiler acquisition and MoonBit for installation
orchestration. A compiler need not already be installed: mise 2026.9.4 was
verified to acquire the pinned compiler and core into a separate directory,
after which that compiler bundled core and executed a MoonBit script. The
earlier conclusion that a fresh checkout requires a PowerShell bootstrap was
too strong. mise can also load `toolchain.json` through `vars._.file`, avoiding
a second copy of the version and checksum pins.

The bootstrap entry point acquires an invocation-specific runtime, then runs
`scripts/bootstrap.mbtx` to stage, bundle and validate the compiler/core pair.
It runs outside the installation being replaced so Windows does not need to move
the currently executing compiler. A directory lock excludes simultaneous
promotions; a failed promotion restores the previous installation. Successful
setup removes the temporary runtime, while retaining the previous installation.
mise 2026.9.4 is the minimum verified acquisition implementation.

Windows registry pack files are read-only. The Wasm filesystem runtime rejects
`chmod`, so cleanup uses Windows `attrib.exe` solely to clear that attribute,
after validating containment and rejecting links or special files. Traversal,
deletion, installation and recovery remain MoonBit code. This narrow OS boundary
does not require a PowerShell script. Track the unsupported filesystem operation
and the scope of installation/recovery validation in #82.

## Consequences

The current bootstrap supports Windows x64. Other hosts need separately verified
artifacts and setup scripts. MSVC/Windows SDK remain prerequisites.
CLI/CI verification cannot substitute for real GPU, IME, or accessibility tests.

## Evidence

See [environment](../verification/environment.md) and [P0 results](../verification/p0.md).
The installation and checksum format follow the
[official MoonBit distribution](https://www.moonbitlang.com/download/).
