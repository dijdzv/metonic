# Development checks

Recorded: 2026-09-06.

## Runtime and manual CI

With mise 2026.8.5 and Node 26.8.1, `mise run verify` and
`mise run verify-native` passed the JS, WasmGC, and Windows native contract
tests, frontend execution probes, valid isolated builds, and four compile-fail
fixtures per target. These remain console tests, not GUI verification.

The manual-only workflow no longer classifies changed paths. All verification
steps remain enabled on dispatch, and artifact upload steps retain `always()`.
The earlier scope classifier and its tests were removed rather than translated.
`moon run scripts/verify-docs.mbtx` checks tracked Markdown links; positive and
missing-link fixtures were exercised during its PowerShell-to-MoonBit migration.

## Pre-commit

The built-in `mise generate git-pre-commit --write --task pre-commit` command
installed the local hook. No separate hook package is required.

The initial lightweight hook was tested in an isolated temporary Git repository:

- Accepts a valid Markdown filename containing a space.
- Preserves both the Git index tree and working file hash with partial staging.
- Returns failure for a missing relative Markdown link.
- Returns failure for staged trailing whitespace.

Those observations describe the earlier hook, not the current full local gate.
The current `scripts/pre-commit.mbtx` rejects tracked unstaged changes, runs
formatters, static checks and the local test suite, and stops if formatting changes
tracked files. The author reviews and stages formatting changes explicitly; the
hook never stages or stashes them. It verifies the working tree, not a separately
materialized index snapshot. Temporary fixtures remain outside version control.

`native:binding` includes the font-backed text fixture verification, so the hook
does not also run `text:verify` separately. Browser GPU tests use SwiftShader and
native binding tests request a software adapter during the full local gate.
Physical GPU checks are recorded separately in the relevant verification documents.

The workflow accepts `workflow_dispatch` only. It is available for manual diagnosis
and does not duplicate local checks on PR or push. Main requires a PR, linear
history and resolved conversations; it has no required status check. Force push
and branch deletion remain disabled.
