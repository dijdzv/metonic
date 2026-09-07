# Browser verification process ownership

## Contract

The browser verification tasks run a MoonBit supervisor in the pinned Wasm
runtime. The supervisor starts the loopback development server and then the Node
adapter for either `async` or `headless` verification. The adapter retains direct
Playwright operations and normal browser shutdown. Application targets remain
JavaScript and WasmGC, each executed by Chromium.

Server readiness must match `http://127.0.0.1:4173/` followed by a newline within
10 seconds. A failed readiness check prevents verifier startup. The session has
a 300-second deadline. Early server exit, nonzero verifier exit and excessive
output are failures. Each of the four output streams retains a bounded prefix
of at most 64 KiB rather than accumulating arbitrary process output.

On Windows, verifier cancellation targets its PID and descendants using
`taskkill /PID <pid> /T /F`. The helper is protected from cancellation while it
finishes. Direct-process termination is a fallback and must not be represented
as proof that descendants were terminated. The Windows command's PID, tree and
force options are documented in [Microsoft's taskkill reference](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/taskkill).

## Reproduction

Run `mise run browser:supervisor-test` for process fixtures. The task builds the
fixture artifact before running the supervisor package tests. Run
`mise run browser:async` and `mise run browser:headless` for browser integration;
repeat with `METONIC_GPU_BACKEND=swiftshader` for the software adapter.

Supervisor logs are separate from pixel and application-state artifacts:

```text
.work/browser-supervisor/<async|headless>/<default|swiftshader>/
  server.stdout.log
  server.stderr.log
  verifier.stdout.log
  verifier.stderr.log
  result.json
```

The dedicated tests must establish normal completion, bad and missing readiness,
early server exit, verifier exit failure, output overflow, and timeout cleanup
of a descendant observed alive before cancellation. Test success is separate
from the four real browser runs and the complete pre-commit gate.

## Verification record

On 2026-09-07, `browser:supervisor-test` passed all eight tests through the mise
entry point. The timeout fixture reported its descendant PID and observed it
alive before cancellation; the subsequent PID-filtered process listing no
longer contained that PID. Windows command output is inspected as bytes because
localized output is not necessarily UTF-8.

Both `browser:async` and `browser:headless` passed with default adapter selection
and explicit SwiftShader. Each run exercised both JS and WasmGC application
targets. All four supervisor results reported `outcome: success` and no cleanup
warning. The existing Playwright pixel, input, text and negative assertions were
retained. This record does not represent a hosted CI run.

## Limits

This is ownership of processes launched for local verification. It does not
guarantee orphan recovery after an external parent crash, termination of the
supervisor itself, or OS failure. It does not establish real IME, physical input
or OS accessibility support. The manual workflow remains opt-in; automatic
PR/push CI does not duplicate local verification.
