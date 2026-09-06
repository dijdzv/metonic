# Development checks

Recorded: 2026-09-06.

## Runtime and CI scope

With mise 2026.8.5 and Node 26.8.1, `mise run verify` and
`mise run verify-native` passed the JS, WasmGC, and Windows native contract
tests, frontend execution probes, valid isolated builds, and four compile-fail
fixtures per target. These remain console tests, not GUI verification.

`pwsh -NoProfile -File scripts/ci-scope.Tests.ps1` passed documentation,
source/configuration, mixed, rename, empty-change, and invalid-input cases.
`pwsh -NoProfile -File scripts/verify-docs.ps1` passed tracked Markdown link checks.

## Pre-commit

The built-in `mise generate git-pre-commit --write --task pre-commit` command
installed the local hook. No separate hook package is required.

An isolated temporary Git repository verified that the check script:

- Accepts a valid Markdown filename containing a space.
- Preserves both the Git index tree and working file hash with partial staging.
- Returns failure for a missing relative Markdown link.
- Returns failure for staged trailing whitespace.

The hook performs no automatic formatting or staging. Link and formatting checks
read the working tree, so these checks do not certify an isolated staged snapshot.
Temporary fixtures remain outside version control.
