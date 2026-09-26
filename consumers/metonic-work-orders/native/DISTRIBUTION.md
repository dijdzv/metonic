# Windows distribution

`WorkOrders.exe` is a Windows x64 release build. Keep `accesskit.dll` and the
`assets` directory beside it. The packaged license directory contains the
notices for the pinned compiler and native dependencies. `distribution.json`
records the exact framework revision and SHA-256 of each packaged file.

The release entry has no development controller. This application currently
keeps edits in memory and is an evaluation fixture, not a durable work-order
product. Closing it discards changes until the Phase 6 persistence path is
implemented.
