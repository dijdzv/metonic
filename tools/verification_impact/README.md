# Verification impact selection

This package consumes the pinned Moon build tool's check-time `packages.json`.
It follows implementation, black-box test and white-box test dependencies in
reverse, starting from the deepest package containing each changed source path.
It returns owned package paths, not individual tests or a purity judgement.
Unknown paths and changes outside the supported source suffixes select the whole
input graph. Missing required metadata is an error, not an empty selection.

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

## Verification input inspection

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
The fingerprint format is version 2; earlier records do not match it.

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
identity or correspondence to a pushed Git tree. Installed hooks still run the
full gate; no automatic cache reuse is enabled.

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
fresh graph. The CLI must not be connected to a skipping hook until graph export
and freshness are established for all required checks.

The result covers only the supplied graphs. Packages shared across graphs retain
the union of dependency edges and are included if any graph identifies them as
owned. It does not refresh or authenticate metadata, run tests, or cache results.
Existing hooks still run their normal verification. Hook integration must first
provide fresh graphs for every required workspace/target, classify critical and
environment-dependent checks, and account for pushed Git revisions and successful
verification of identical inputs. A stale graph must not authorize skipping tests.
