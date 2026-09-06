# Development guide

## Windows x64 setup

Install mise, PowerShell 7 (`pwsh`), and Visual Studio C++ x64 build tools with the Windows SDK.
From the repository root:

```powershell
mise trust
mise install
mise run bootstrap
mise run doctor
mise run hooks:install
mise run verify
mise run verify-native
```

`bootstrap` installs the exact compiler/core pair in `toolchain.json` with SHA256
verification. `doctor` rejects a different version. Tool binaries, caches, and
temporary diagnostics stay under ignored `.tools`, `_build`, and `.work` paths.

Run `mise run fmt` to format. For other MoonBit commands, use the project wrapper:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/moon.ps1 version --all
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/moon.ps1 check --target js
```

This explicit wrapper avoids falling back to an older global executable when
Windows PATH entries are ordered differently by a parent shell.

## Local pre-commit checks

`mise run hooks:install` uses mise's built-in Git hook generator. Run it once per
clone with the default Git hooks directory; it replaces `.git/hooks/pre-commit`,
so preserve any custom hook before running it. Git must be able to find `mise`
and PowerShell 7 on PATH.

`mise run pre-commit` can also run the checks manually. It checks staged changes
for whitespace errors. Staged Markdown changes trigger local link checks;
staged MoonBit source or package changes trigger `moon fmt --check`.
Formatting and link checks inspect the current working tree, including unstaged
edits. The hook never rewrites, stages, or stashes files, so partial staging is
preserved; it is not verification of an isolated staged snapshot. Full contract
tests remain in the verification tasks and PR CI.

## Toolchain updates

Check the current non-dev version on the official MoonBit distribution. Resolve
versioned compiler/core URLs, verify the compiler checksum against its published
SHA256, and record both archive hashes in `toolchain.json`. Update that pin in a PR,
run `bootstrap`, migrate source/configuration where necessary, then run both
verification tasks. CI must use the same committed pin.

Node 26.8.1 runs generated JavaScript; it is not a native product dependency. There are
no JS packages to install yet. Use pnpm with a committed lockfile if they are added.
Rust toolchain/lockfile selection belongs to the first native bridge implementation.

## Repository layout

| Path | Purpose |
| --- | --- |
| `rpc/core` | Typed contract and in-process binding experiment |
| `examples/p0/backend/api` | Target-independent sample application contract |
| `examples/p0/backend/handlers` | Sample backend implementation |
| `examples/p0/frontend/app` | Contract-only frontend build probe |
| `scripts` | Bootstrap, formatting, and verification entry points |
| `docs/adr` | Architectural decisions and proposals |
| `docs/verification` | Reproducible experiments, evidence, and limitations |

`local/p0` is an unpublished experimental module identifier. It is not a public
package namespace or stable API commitment.

## Recording experiments

Keep a concise technical record: purpose, versions, commands, observed results,
unexecuted checks, and consequences. Prefer reproducible tests over a transcript
of terminal output. Raw logs belong in ignored local directories or CI artifacts.
Do not commit conversation transcripts, personal handoff notes, credentials, or
machine-specific absolute paths.

Test only the claims a change makes. Console execution is not GUI validation.
Internal semantic actions do not validate OS accessibility. Text insertion does
not validate Japanese IME composition. A runtime-disabled listener does not prove
that development tooling was excluded from a production binary.

## Work and release flow

- Use short-lived branches and small PRs. Squash merge after review and required checks.
- Main requires a PR, resolved review conversations, and `Windows verification`
  against the current base. Force pushes and deletion are prohibited, including for administrators.
- Use issues for task tracking with a purpose and completion criteria. Use `Closes #N`
  only for a completed task; use `Refs #N` for partial progress.
- Release from verified main commits with immutable `v0.x.y` tags. Add a maintenance
  branch only when supporting an older version in parallel becomes necessary.

## CI events and scope

| Event / change | Work performed |
| --- | --- |
| PR: documentation or license text only | Scope-classifier checks and local Markdown link validation |
| PR: source, toolchain, scripts, workflow, or any unrecognized path | The lightweight checks plus pinned bootstrap and native/JS/WasmGC verification |
| Manual dispatch | All checks, regardless of changed paths |
| Ordinary branch or main push | No duplicate verification run |

The required job always runs for PRs; only its expensive steps are conditional.
Unknown or empty change sets select full verification. Renames include both old
and new paths. A failing classifier or link check fails the job.

There is no push-only task yet. Artifact packaging or publishing will use a
separate release-tag workflow when distribution exists, rather than rerunning
the PR test suite after every merge.

Development automation is specified in [ADR 023](adr/023-development-automation.md).
