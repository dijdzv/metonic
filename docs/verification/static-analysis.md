# MoonBit structural checks

`mise run static:verify` parses every tracked or untracked, non-ignored `.mbt`
and `.mbtx` source in this checkout, then scans the same inventory with one
structural rule. The normal local pre-commit lane runs this command after the
MoonBit compiler checks. Manual CI dispatch runs it on Windows as well.

The MoonBit script `scripts/prepare-static-analysis.mbtx` downloads and checks
the SHA-256 of ast-grep 0.45.3, Tree-sitter CLI 0.27.0 and a pinned
`moonbitlang/tree-sitter-moonbit` source snapshot. It applies the small grammar
patch in `tools/static_analysis/parser.patch`, generates the parser and builds
an MSVC DLL under `.work/static-analysis`. The patch adds `errdefer` and tuple
binders in `for ... in` loops, which the pinned compiler accepts but the
unpatched grammar misses. The generated DLL and tool executables are checked
before reuse; the release archives and source snapshot are checked on every
preparation. These files are local build inputs, not browser or native release
assets.

The parser gate checks the parse status and count for the complete source
inventory. It also confirms that deliberately malformed syntax fails. This
independent gate is necessary because an ast-grep rule search alone can miss a
Tree-sitter `MISSING` recovery node. The ast-grep inspection count must equal
the parser inventory count and load exactly one rule. An omitted file, unloaded
rule or parse error fails verification.

The first rule, `no-signal-write-in-memo`, detects a direct `.set(...)` call
inside the callback passed to `@reactive.Memo::new`. Its four fixtures cover
block and expression callbacks, a write outside the Memo, and a callback
returned by the Memo. This is a syntactic guard: it cannot prove that the
receiver is a Signal, trace helper calls or establish evaluation lifetime.
MoonBit's type checks and runtime tests remain responsible for those contracts.

The parser, rule and fixtures were validated locally on Windows x64 against
527 current source files. Manual CI dispatch supplies a second Windows
environment check; until that run passes, hosted reproducibility is not yet
established. The isolated parser patch is not an upstream release or a posted
pull request.
