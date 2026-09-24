# Initial usable release criteria

Status: Phase 4 acceptance scope frozen on 2026-09-24 and verified for the
bounded initial usable path on 2026-09-25. No version tag has been announced.
The [acceptance record](verification/phase4-acceptance.md) and
[open-Issue audit](https://github.com/dijdzv/metonic/issues/566)
separates the finite required work below from subsequent and deferred work.

## Targets and guarantee

The primary application targets are Windows x64 native and a WebGPU browser with
WasmGC. Browser JS is a MoonBit compilation backend for comparison and regression
checks, not a DOM renderer or a required default distribution artifact. Both
browser backends render through the WebGPU canvas and use DOM elements for input
and semantics. The P0 release package selects WasmGC; the independent Notes
consumer currently packages both selectable browser backends. WasmGC still needs
a small JavaScript host for browser APIs and startup. See
[ADR 024](adr/024-browser-gpu-probe.md) and the
[browser host boundary](browser-host-boundaries.md).

Support is limited to the environments actually verified. A successful Chromium
headless run with a software adapter does not certify other browser engines,
physical IME behavior, or every GPU. Native checks exercise Windows x64; they do
not certify every Windows installation or graphics driver. Unsupported WebGPU or
WasmGC must report startup failure instead of silently changing backends.

Application authors pin a Metonic source revision, rather than depending on a
published stable package. The [source-consumer entry](application-entry.md#external-workspace-builds)
checks that pin and prepares only the selected target. Public paths remain
experimental: a later revision may make a breaking API change, but its change
must include an application migration note and an updated independent consumer.
Pinning a revision preserves that revision's behavior; it is not a long-term
binary or semantic-version compatibility promise.

## Application-author acceptance

| Need | Public boundary and current example | Evidence to keep current | Remaining release question |
| --- | --- | --- | --- |
| State, derived values, and retained UI identity | `core/reactive` Graph/Signal/Memo/Scope; `core/application` Control/Binding; independent [Notes consumer](../consumers/metonic-notes/README.md) | [ADR 035](adr/035-reactive-graph-ownership.md), [lifecycle verification](verification/reactive-notes-lifecycle.md), Notes model and 1,000-memo scenario | Confirm ordinary application composition does not need host-internal imports. |
| Text editing, focus, selection, IME, accessibility | Portable application editor/control contract, native AccessKit adapter, browser semantic DOM input | [Application entry](application-entry.md), [browser input checks](verification/browser-input.md), recorded physical input acceptance in the [Notes consumer](../consumers/metonic-notes/README.md#physical-native-input-acceptance) | State the tested OS, browser and assistive-client scope; keep real IME observations distinct from synthetic tests. |
| Independent asynchronous work and cleanup | `core/application_task` Driver/Operation; Scope-owned `core/reactive_task.Resource` and `Source` | [Application entry](application-entry.md), [async-state contract](adr/036-async-derived-state.md), and [two-host paired application](verification/async-pair-phase4.md) | Keep driver cleanup and the public state contract aligned as APIs evolve; the demonstration data is not a network/storage guarantee. |
| Portable and platform-specific resources | `capabilities/clock` and `capabilities/http`; native/browser host storage, clipboard and asset packages | [ADR 033](adr/033-capability-platform-boundaries.md), [resource table](application-entry.md#resource-responsibilities) | Keep distinct storage, permission and close guarantees explicit; do not invent a universal platform interface. |
| Save, restore, close, and distribution | Notes source consumer with selected-target builds and native/browser packages | [Notes build and package verification](../consumers/metonic-notes/README.md#build-and-verification), [external ESM consumer](verification/external-esm-consumer.md) | Complete the final integrated package checks; distinguish relocation tests from clean-machine installation. |
| Development control without production exposure | Native CLI/MCP adapter and browser DOM automation on development entries | [Application entry](application-entry.md#native-development-control), [browser development control](application-entry.md#browser-development-control), package-exclusion checks | Recheck exclusion on the final consumer artifacts after required changes. |

The acceptance example must use the framework through its source entry and
published application-facing packages. Copying a host implementation, editing a
registry package, or requiring application-specific infrastructure to repair a
framework contract does not satisfy the boundary. The existing Notes source is
one independent consumer; a smaller second example with different state and
asynchronous dependencies must test that the API is not tailored to Notes.

## Frozen required scope

Atomic admission of independent requests
[#570](https://github.com/dijdzv/metonic/issues/570), keyed async
result/derivation state [#571](https://github.com/dijdzv/metonic/issues/571),
and the independent two-host usage check
[#572](https://github.com/dijdzv/metonic/issues/572) are implemented and
verified. The external ESM consumer's native GPU integration is verified through
the public source entry and an independent ESM Notes app. The published GPU
package still needs an upstream correction [#453](https://github.com/dijdzv/metonic/issues/453),
but that publication is no longer a Metonic release prerequisite. The pinned
structural checker [#568](https://github.com/dijdzv/metonic/issues/568) parses
the project fail-closed and runs a tested rule in the local hook and manual CI.
Its supported syntax and limits are recorded in the
[static-analysis verification](verification/static-analysis.md). The accepted
design [#567](https://github.com/dijdzv/metonic/issues/567), completed async
implementation and source integration passed the bounded final checks in the
[acceptance record](verification/phase4-acceptance.md). A future version tag or
broader support promise requires its own decision.

The other open P2 tasks cover subsequent improvements and upstream proposals;
their currently working product paths stay in place. P3 tasks include optional
gRPC and intermittent problems with explicit recurrence triggers. A fresh
reproduction that demonstrates a release defect can change this scope, but its
evidence and impact must be recorded on the relevant Issue before promoting it.

## Release gate and known limits

Before calling the initial usable release complete:

1. Keep the [open-Issue classification](https://github.com/dijdzv/metonic/issues/566)
   and finite required scope above current. Recurrence-only and external-release
   work must retain evidence and a restart condition; their existence alone
   does not prove a current product bug.
2. Implement and verify [async-derived-state integration](adr/036-async-derived-state.md)
   on native and the primary browser backend, with JS comparison coverage where
   the shared browser contract needs it. Verify pending, refresh with prior value,
   failure, cancellation, replacement, Scope disposal and two independent results.
   A successful B-path Resource check is not evidence that this C-path exists.
3. Validate a pinned [MoonBit structural parser and useful rule](https://github.com/dijdzv/metonic/issues/568)
   on real source and valid/invalid fixtures. Parsing failure must fail the check.
4. Keep the verified external ESM source entry working without changing GPU
   dependencies in the registry cache or duplicating the GPU bridge. The
   temporary workspace package-scope marker remains until #453's upstream
   correction is available; upstream publication is a separate P2 improvement.
5. Run the relevant native/browser input, editing, persistence, async,
   accessibility, resource, performance and packaged-artifact regressions after
   integration. Report any manual or machine-specific evidence separately.
6. Reconcile this contract, the [README](../README.md), public API documentation,
   and the independent consumer's instructions with the actual shipped result.

Current limits include a 1,024 UTF-16-unit browser input bound, a 1 MiB native
snapshot read/write bound, origin-scoped browser `localStorage` without backup or
cross-tab coordination, bounded task admission, no automatic retry of unexpected
task failures, and no general image control or layout virtualization. The
[application entry](application-entry.md#current-limits-and-verification) defines
the exact contracts. These limits are not hidden by a successful demo.

The release does not promise every OS, browser, GPU, IME, assistive client or
installation; unlimited application size; a full component catalog; cloud
sync; gRPC; multiple windows; plugins; or stable API compatibility across
unpinned revisions. Later support decisions require their own acceptance evidence.
