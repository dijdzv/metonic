# Metonic Notes for Windows

Keep `Memo.exe`, `accesskit.dll`, `assets/` and `licenses/` together. Start
`Memo.exe` from any working directory. The GUI executable opens no additional
console window. No MoonBit, Rust, mise, Node or source
checkout is needed to run the package. This experimental build targets Windows
x64 and requires a working graphics driver. AccessKit additionally imports
`VCRUNTIME140.dll`, supplied by the Microsoft Visual C++ x64 runtime; that runtime
is a system prerequisite and is not copied from the developer's Windows folder.
This package has not yet been verified on a clean Windows installation.

Create a memo with New, select an item in the scrolling list, edit, then Save or
Discard. Move up and Move down change the selected memo's order. Delete requires
confirmation. Unsaved changes prevent normal app close.
Data is stored under `%LOCALAPPDATA%/MetonicNotes` unless `METONIC_NOTES_DATA`
explicitly selects another directory. Only one writer may open that store.
Keep a backup of important memos; this experimental local store does not provide
device synchronization. Load/save errors expose retry instead of silently
discarding existing data.

`package.json` lists the shipped files, byte counts, SHA256 values and framework
source revision. It is not a cryptographic signature. Development probes,
CLI/MCP adapters, object files and generated C sources are not included in the
file allowlist. `verify:native-package` separately verifies release-control
exclusion and relocated production editing; packaging alone does not establish them.

## Dependency notices

The `licenses/` directory contains the framework MIT/Apache texts, MoonBit core
LICENSE/NOTICE, prepared async/window/windowing/cosmic/clipboard licenses, Chicle,
swash, skrifa,
yazi, zeno, wgpu-mbt, HarfBuzz LICENSE/NOTICE, and the Rust dependency attribution
reports. `assets/OFL.txt` applies to Noto Sans JP. `rust-inventory.json` records
the Rust report inputs and output hashes; that conservative graph includes
build-time tools that are not deployed as executables.

The native MoonBit runtime and `moonbitlang/x` fs/unicode modules use Apache-2.0;
the included `LICENSE-APACHE` supplies its terms. Their source headers attribute
Copyright 2026 and Copyright 2025, respectively, to International Digital Economy
Academy. The pinned framework defines prepared modifications to async, window,
cosmic, proton_clipboard and AccessKit; retain these notices with the binary
distribution. The clipboard dependency's Windows writer includes the framework's
documented window-ownership correction.
