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
