# Native CLI and MCP verification

Date: 2026-09-06.

The launch-scoped control experiment uses the same native client from the JSON-line
CLI and MCP adapter. See [ADR 026](../adr/026-launch-scoped-native-control.md).

## Local evidence

- Five transport test groups passed: response correlation, failed capture,
  pending request timeout, cancellation, queue limits, malformed/unknown replies,
  early process exit, bounded diagnostics, and close behavior.
- The shared client drove snapshot, move, activate, and capture on RTX 3060/DX12
  and Microsoft Basic Render Driver. Complete pixel comparisons passed, as did
  stale revision rejection and concurrent capture rejection.
- The official MCP SDK client connected to the external stdio server, listed all
  five tools, moved the rectangle to (10, 20), activated it, and received a PNG for
  frame 1/revision 2. Complete pixel comparisons passed on both adapter modes.
  Stale mutation and invalid resize were rejected without changing scene state.
- A CLI JSON-line sequence returned the same state transitions and PNG content.

Versions: Node 26.8.1, MCP server/client SDK 2.0.0, Zod 4.5.4; native versions are
recorded in the [GPU probe record](native-headless.md). SDK tests establish
interoperability with that client, not every MCP host or legacy protocol revision.

## Reproduction

After the setup in the [development guide](../development.md):

```powershell
mise exec -- pnpm install --frozen-lockfile
mise run native:build
mise exec -- node --test tools/devtools/native-client.test.mjs
mise exec -- node scripts/verify-native-control.mjs
mise exec -- node scripts/verify-native-mcp.mjs
$env:METONIC_GPU_FALLBACK = '1'
mise exec -- node scripts/verify-native-control.mjs
mise exec -- node scripts/verify-native-mcp.mjs
Remove-Item Env:METONIC_GPU_FALLBACK
```

Images and JSON evidence are stored in `.work/native-control` and `.work/native-mcp`.
The development processes use per-launch temporary capture directories and remove
them on normal shutdown. No desktop input automation is involved.

## Boundaries

This is an offscreen, dedicated child-process probe. It does not attach to existing
windows, produce semantic node references, test Windows IPC ACLs, or establish
nonblocking UI-thread scheduling. Production accessibility and exclusion of the
development composition still require paired artifact tests. Cancellation ends
the session; it cannot prove that an already submitted action was never applied.
The local pre-commit gate runs these checks. Automatic PR/push CI does not repeat
the same verification; manual dispatch remains available for hosted diagnosis.
