# Semantic model probe

Date: 2026-09-06.

The initial MoonBit model contains a toggle button and text input. Immutable
snapshot nodes carry role, name, value, enabled/focused state, selection, and a
session/window/node/generation reference. Operations validate the complete
reference before mutation. Removing and recreating the input advances its
generation; stale references cannot act on the replacement.

Seven model tests pass on JS and WasmGC. They exercise stale and cross-window
references, role checks, exclusive focus, disabled actions, immutable snapshots,
terminal disposal, and UTF-16 selection boundaries. The supplementary Unicode
character in `A😀B` occupies two UTF-16 code units; selection inside that pair is
rejected. This is not grapheme-cluster navigation or text shaping.

The native JSON-line host now returns `nodes` and `semantic_revision`. Semantic
activate, focus, text, selection, enabled state, removal, and recreation operations
validate their node reference and optional `expected_semantic_revision`. Ordinary
activate uses the same button action and rejects a disabled or removed button.
Scene and semantic revisions remain separate.

`mise run native:semantics` passed with RTX 3060/DX12 and Microsoft Basic Render
Driver. A semantic button action changed the rectangle color and passed full RGBA
pixel comparison. Text/selection, focus exclusivity, disabled actions, generation
reuse, cross-window references, and stale semantic revisions also passed. Existing
native headless and MCP regression checks passed with software DX12.

The model's session/window numbers currently identify one process-local tree;
they are not globally unique attach capabilities. The external client's launch
UUID and process ownership are a separate boundary. This probe has no cross-process
node routing. The text input has semantic data but no rendered text or layout bounds.

Model and command tests do not establish
Windows UIA/AccessKit behavior, a browser accessibility tree, actual text rendering,
IME composition, or production exclusion of development adapters.

Run `scripts/moon.ps1 test examples/p0/semantics --target js` or `--target wasm-gc`
with the pinned toolchain. The public architectural boundaries remain those in
[ADR 023](../adr/023-development-automation.md); AccessKit is not yet adopted.
