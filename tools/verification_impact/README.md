# Verification impact selection

This package consumes the pinned Moon build tool's check-time `packages.json`.
It follows implementation, black-box test and white-box test dependencies in
reverse, starting from the deepest package containing each changed source path.
It returns owned package paths, not individual tests or a purity judgement.
Unknown paths and changes outside the supported source suffixes select the whole
input graph. Missing required metadata is an error, not an empty selection.

## Hook partition planning

`--partition-tests <policy> <target> <inventory>` reads `verification.json` and an
inventory containing `available` and `affected` package-path arrays. It preserves
inventory order, assigns critical packages supported on that target plus affected
packages to `pre_commit`, and assigns the remaining packages to `pre_push`.
Packages appear only once. Missing affected or required critical packages are
errors. The caller must provide fresh target-specific inventory and dependency
selection; this command does not discover packages or infer purity. `pre_push`
is a remainder plan, not authorization to skip a previously verified test.

The repository's paired hooks use recorded input discovery around these plans.
`full_gate_tasks` remains the fallback when a record cannot certify prior work.
See the development guide for installation and supported checkout cases.

From the configured repository environment, run
`moon run scripts/plan-local-verification.mbtx -- <target>` to refresh root-module
check metadata and plan against tracked changes from HEAD plus untracked files.
The script removes the previous metadata file before checking, requires a fresh
replacement, and filters packages using their declared supported targets.
`--run-commit` after the target executes the selected package tests through the
existing verification runner, including native compiler setup when needed.

This root-module runner is not a commit hook: it includes unstaged changes, does
not format, does not cover the separate browser/native workspaces or integration
gates, and does not save reusable success records. Changes outside the supported
source paths conservatively select all root packages supported on that target.
The recorded hook wrappers supply pushed refs and input records separately.

## Workspace graph plans

The pinned Moon supports `-Z rr_export_package_graph` before the `check`
subcommand. It emits `package_graph.dot` in the target directory, including
source and test dependencies. The format is unstable: the reader rejects unknown
statements, node kinds and unresolved edges instead of silently ignoring them.

`verification_impact_cli --read-export <package_graph.dot>` displays normalized
package names and dependencies. `--plan <config.json> <absolute-changed-path>...`
combines exported graphs and maps owned packages to existing directories. The
configuration has this shape (paths are resolved from the working directory):

```json
{
  "modules": {
    "local/p0": ".",
    "local/browser_host": "browser_host/app",
    "local/native_host": "native_host"
  },
  "graphs": ["<browser-target-dir>/package_graph.dot", "<native-target-dir>/package_graph.dot"]
}
```

Module directories must be their package source roots. Every mapped package must
have a package manifest. External nodes remain in dependency traversal but are
not test destinations. Changes outside mapped source paths select all mapped
packages. Callers must supply every owned module and required fresh target graph;
this CLI cannot prove that a configuration is complete or up to date. Its output
is a reviewable plan, not permission to skip verification.

## Push revision inspection

`verification_impact_cli --push-plan -` reads Git pre-push records from stdin
(at most 1 MiB); a filename can replace `-` for reproduction. It resolves each
non-deletion object to a local commit and tree using Git, preserving destination
refs and deletion records. Missing/non-commit objects fail rather than falling
back to HEAD. It does not execute tests or certify working-tree contents. The
runner still needs successful-input records and committed-input verification.

`--run-push-checkout <directory> <input-file-or-dash> <command> <args>...` validates
all non-deletion refs against the checkout before invoking the command once.
Empty/deletion-only pushes invoke nothing; multiple refs with the same tree
share one invocation. A different tree is rejected before execution, even when
an earlier ref matches. This entry point does not prepare alternate checkouts or
reuse success records, and is not yet an installed pre-push hook.

`--run-checkout <directory> <expected-tree> <command> <args>...` runs a command
in an existing checkout only when its HEAD tree matches the expected tree and
Git reports no staged, unstaged or untracked changes. It repeats these checks
after the command and rejects nonzero exit status. This does not create or
switch checkouts, write a success record, or install a pre-push hook.

This guard is only the tracked-checkout part of verification. Ignored inputs,
toolchain and environment identity need separate fingerprints. Index entries
marked assume-unchanged or skip-worktree are rejected. Git clean filters
and changes reverted during execution are
not authenticated by a clean status result. Do not use this guard alone to
authorize cached verification or certify immutable pushed inputs.

`--record-checkout <directory> <expected-tree> <config> <record> <command> <args>...`
combines that guard with the successful-record protocol below. The config context
must also contain `tree` equal to the expected Git tree and `checkout` equal to
the checkout's canonical path, and its `command` must match the invocation.
Invalid attempts invalidate any previous success under the record lock. Use
absolute input paths when the caller's directory differs from the checkout;
fingerprints are evaluated in the caller's directory. These checks still require
a complete input inventory and do not install or enable skipping in hooks.

## Verification input inspection

`--run-recorded-push <directory> <input-file-or-dash> <config> <record>
<commit-command-json> <full-command-json> <remainder-command-json>` combines the
checkout guard with record selection. Commands are JSON arrays. It validates all
non-deletion pushed trees before executing anything; empty and deletion-only
updates run nothing. A matching record must identify the same tree, canonical
checkout and commit command. Its comparison base must be a full resolved commit
ID and an ancestor of every pushed commit. The remainder command receives that
base as its final argument, and inputs and the success record are checked again
after it finishes.

Missing or mismatched success, changed inputs, an unrelated base, or an unborn
base select the full command. Invalid configuration and input read errors fail
explicitly. Different pushed trees still require a matching checkout; this command
does not create one. Callers must supply a complete tool/dependency/environment
input configuration and trusted lane commands. This generic dispatcher does not
construct that configuration or install the repository hooks.

`--source-inputs <packages.json> [--metadata <packages.json>]... <absolute-package-directory>...` enumerates
the source maps of selected packages and their transitive dependencies. Test
sources and test-only imports are included for selected packages; dependencies
contribute implementation sources/imports, not their own unrelated test suites.
It requires complete metadata and rejects unresolved
dependencies. Root check metadata can reference bundled standard-library
packages without defining them; add a fresh standard-library check metadata file
through `--metadata`. That source inventory does not replace fingerprints of the
bundled compiled standard library actually consumed by the command.
The CLI includes each required package manifest and its nearest module manifest,
plus workspace/lock files in that module directory. It returns `packages` as well
as `files` for further input planning. A missing package/module manifest is an
error. Workspace files above the module root, external assets and toolchain
binaries still require explicit inclusion; this is not a complete verification key.

`verification_impact_cli --fingerprint <config.json>` records raw Git blob hashes
for the explicit `files` array and sorted `context` string fields. Context must
include `target`, `toolchain`, `command` and `policy`. Paths are canonicalized;
duplicate paths and input ordering do not change the output. Raw file bytes are
hashed without Git clean filters, so the record describes actual working files.

An optional `trees` array adds recursively enumerated directory inputs, including
hidden files and empty directories. Each fingerprint enumerates them again so
new or deleted inputs invalidate an earlier record. Tree entries must be real
directories; symlinks and special files encountered below them are rejected.
Store result records, locks and generated test outputs outside these input trees.
The fingerprint format is version 3; earlier records do not match it.

An optional `environment` array names variables read from the running process on
every fingerprint. Sorted unique names and Git blob hashes of JSON-encoded values
are recorded; absent and empty values differ. Values are sent to Git over stdin,
without writing them to a temporary file or command arguments. These hashes are
input identities, not encrypted secrets. The caller must enumerate the variables
that affect its commands, including compiler and search-path settings. This does
not discover environment dependencies or hash the executables found on PATH.

Trees complement explicit `files`; they do not discover transitive dependencies
or external assets automatically. Include all required source trees and explicit
configuration/tool inputs. Before/after comparison still cannot detect a
temporary change that is reverted while the command is running.

This is not a success record or a complete cache key by itself. The caller must
enumerate all transitive implementation/test inputs, manifests, locks, generated
sources and relevant configuration, obtain the actual toolchain/environment
identity, and compare inputs before and after a successful verification. Caller
supplied context is not independently authenticated. No test is skipped by this
command and no Git object is written.

## Successful verification records

`verification_impact_cli --record <config.json> <record.json> <command> <args>...`
runs a command and saves success only if its exit status is zero and the input
fingerprints before and after execution agree. The configuration uses the same
fields as `--fingerprint`; `context.command` must equal the compact JSON encoding
of the command/argument array. The record's parent directory must already exist.

A retry invalidates an earlier success first. A per-record lock prevents concurrent
writers; normal failure and cancellation release that lock. Success is published
by renaming a completed temporary file. Abrupt termination can leave the lock:
do not automatically remove it merely because a record is old.

`--match-record <config.json> <record.json>` reports `matches: true` only for a
successful record with the current fingerprint. Missing, malformed or failed
records do not match. Lock contention and input read failures are errors. This
inspection does not keep the inputs fixed after returning or authorize skipping
tests by itself. It does not establish complete inputs, actual environment
identity or correspondence to a pushed Git tree. The repository wrappers add
discovery and Git-tree validation before using this primitive.

## Legacy check metadata

The Wasm CLI in `tools/verification_impact_cli` accepts a metadata filename,
additional graphs through repeated `--metadata <filename>` options, and
absolute changed paths. Generate metadata with a successful `moon check` before
using it. For example, from the repository root in the mise environment:

```text
.tools/moonbit/bin/moon.exe check --target js --deny-warn
.tools/moonbit/bin/moon.exe run tools/verification_impact_cli --target wasm -- _build/js/debug/check/packages.json <absolute-changed-source-path>
```

Not every check mode emits this metadata. In the pinned Moon version, a browser
workspace check with an explicit package selector emits `all_pkgs.json`, which
has artifact locations but lacks the dependency edges required here. It is not
a substitute for `packages.json`, and a pre-existing file is not evidence of a
fresh graph. Checking the entire browser workspace without a package selector
does emit `packages.json` in a fresh target directory:

```text
mise exec -- .tools/moonbit/bin/moon.exe -C browser_host check --target wasm-gc --deny-warn --target-dir ../.work/browser-verification-graph
```

The graph includes workspace members outside `browser_host`, including shared
root packages and generated browser bindings. `--partition-workspace <policy>
<target> <metadata> <absolute-scope> [absolute-changed-paths...]` follows all
dependency edges before restricting execution candidates to the scope directory.
Output paths are relative to that scope; `.` identifies its root package.
Critical package names must also be relative to that scope. The ordinary
`--partition-metadata` command still rejects owned packages outside its metadata
source directory; it must not silently discard other workspace members.

The browser app currently has no Moon package test files. The commit command
checks both browser targets with warnings denied; artifact, DOM and GPU behavior
remain integration checks. An empty package-test inventory is not evidence that
those runtime checks may be skipped.

The result covers only the supplied graphs. Packages shared across graphs retain
the union of dependency edges and are included if any graph identifies them as
owned. It does not refresh or authenticate metadata, run tests, or cache results.
The hook wrappers provide fresh workspace checks, separate runtime gates and
bind prior success to discovered inputs and pushed trees. A stale graph must not
authorize skipping tests; new external input layouts need corresponding collector
updates.

`verification_impact_cli --record-index <checkout> <expected-tree> <config>
<record> <command> [args...]` records a command against staged input, including
an initial commit. Its configuration context must identify `tree`, canonical
`checkout`, serialized `command`, and `base_commit` (the current HEAD commit, or
`unborn` before the first commit), in addition to the fingerprint context fields.
Before and after execution it checks the index tree, unstaged/untracked changes,
hidden index flags and comparison HEAD. Failure invalidates the previous success
record. Committing the same staged tree preserves the input fingerprint.

This only binds the supplied input configuration and command. It does not prove
that the configuration enumerates every dependency, tool or environment input,
and it does not install a hook or authorize a pre-push skip on its own.
