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

Retain `scripts/bootstrap.ps1` for compiler acquisition and installation before
MoonBit is available. Subsequent development automation remains MoonBit. The
current script stages downloads and verifies their hashes, bundles core and
checks versions before moving the existing installation to a backup. Keeping
that backup is recovery material, not proof of automatic rollback if the final
directory move fails. This source-level comparison is not a fresh-machine or
failure-injection test. Revisit the boundary when an existing installer can
satisfy the complete pinned-pair contract. Investigation evidence is in #82.

## Consequences

The current bootstrap supports Windows x64. Other hosts need separately verified
artifacts and setup scripts. MSVC/Windows SDK remain prerequisites.
CLI/CI verification cannot substitute for real GPU, IME, or accessibility tests.

## Evidence

See [environment](../verification/environment.md) and [P0 results](../verification/p0.md).
The installation and checksum format follow the
[official MoonBit distribution](https://www.moonbitlang.com/download/).
