# Metonic Quote Board for Windows

Keep `QuoteBoard.exe`, `accesskit.dll`, `assets/` and `licenses/` together.
Start `QuoteBoard.exe` from any working directory. The GUI executable opens no
additional console. Running the package does not require a source checkout,
MoonBit, Rust, mise or Node. This experimental Windows x64 build requires a
working graphics driver. AccessKit imports `VCRUNTIME140.dll` from the
Microsoft Visual C++ x64 runtime; that system prerequisite is not copied into
the package. Clean-machine compatibility has not yet been verified.

Select an item, increase quantity, choose JPY or USD, and refresh or retry a
failed quote. The quote and rate are deterministic fixtures. Note saves use an
in-memory delayed fixture; saved text does not survive application restart.
This is an API demonstration, not a persistence product.

`package.json` lists files, byte counts, SHA256 hashes and the pinned
framework revision. It is an inventory, not a signature. Development probes,
CLI/MCP adapters, object files and generated C sources are excluded.

## Dependency notices

The `licenses/` directory contains the framework MIT/Apache texts, MoonBit
core LICENSE/NOTICE, prepared async/window/windowing/cosmic/clipboard
licenses, Chicle, swash, skrifa, yazi, zeno, wgpu-mbt, HarfBuzz
LICENSE/NOTICE, and Rust dependency attribution reports. `assets/OFL.txt`
applies to Noto Sans JP. `rust-inventory.json` records the Rust report inputs
and hashes; its conservative graph includes build-time tools that are not
deployed as executables.

The native MoonBit runtime and `moonbitlang/x` fs/unicode modules use
Apache-2.0; the included `LICENSE-APACHE` supplies its terms. Their source
headers attribute Copyright 2026 and Copyright 2025, respectively, to
International Digital Economy Academy. Retain the prepared-dependency notices
with binary distributions.
