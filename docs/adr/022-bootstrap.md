# ADR 022: Development workflow and toolchain

Date: 2026-09-06 · Status: accepted

## Context

The project needs small reviewable changes, reproducible technical experiments,
and a low-overhead release process during early development.

## Decision

Use main as the integration branch, short-lived branches, and squash-merged PRs.
Use version tags for releases. Introduce maintenance branches only when parallel
supported versions require them. Main requires a PR, disallows force pushes and
deletion, and applies protection to administrators. External approval is optional.
The `Windows verification` CI check must pass against the current base branch.
It validates documentation on every PR and adds compiler/runtime verification
for implementation, configuration, or unknown changes. Manual dispatch runs all
checks. Ordinary pushes do not repeat the PR checks; future release-tag tasks
will package or publish artifacts separately.

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

## Consequences

The current bootstrap supports Windows x64. Other hosts need separately verified
artifacts and setup scripts. MSVC/Windows SDK remain prerequisites.
CLI/CI verification cannot substitute for real GPU, IME, or accessibility tests.

## Evidence

See [environment](../verification/environment.md) and [P0 results](../verification/p0.md).
The installation and checksum format follow the
[official MoonBit distribution](https://www.moonbitlang.com/download/).
