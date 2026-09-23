# ADR 033: Separate shared capabilities from environment-specific APIs

## Status

Accepted as the boundary policy for application-facing resources. Existing
Clock/Http packages implement parts of this policy; this decision does not claim
that every adapter or future capability is already available.

## Context

ADRs 031 and 032 express time and bounded HTTP as small injected contracts.
Application task requests own replacement, cancellation and result delivery;
native/browser hosts own input, rendering and teardown. A single universal
runtime or Effect enum would couple independent resources to those lifetimes.

The external memo also demonstrates intentional differences: native snapshots
use asynchronous file IO and a writer lock; browser snapshots use synchronous
origin-scoped storage. An interactive close decision is portable application
policy, while closing a native window and navigating away from a page have
different guarantees. Similar names do not establish interchangeable contracts.

## Decision

Use three distinct boundaries:

| Boundary | Representation | Example |
| --- | --- | --- |
| Shared application meaning and guarantees | Small capability contract, implemented by selected adapters | Clock and bounded Http |
| Environment-specific concept | Environment-specific public package/API | Windows window presentation settings |
| Runtime availability or permission | Explicit availability information where useful, plus operation failure | Access denied after a resource was initially available |

A capability describes an operation available to the caller; it does not grant
OS/browser permission. Compose only required dependencies at application startup
and pass them to the operations that use them. Common application code must not
receive GPU devices, HWND values or DOM objects merely to invoke a portable
operation.

Expose an environment-specific operation only through its environment boundary.
Do not require an adapter returning Unsupported on another environment solely to
make package names symmetrical. When an application has an optional feature,
its environment entry may omit that feature or supply an application-facing
action. The shared UI can then omit/disable the action or offer an alternative;
it need not import the environment-specific API.

Current implementation coverage is not the sole classification criterion. An
operation implemented on one host may still merit a shared contract if its
meaning and guarantees are portable and a real consumer needs that boundary.
Conversely, implementations existing on both hosts do not justify hiding
different permission, synchronization or persistence guarantees behind one API.

Availability discovery cannot promise later success. Operations must retain
meaningful failure reporting when permissions or environment state change.
Distinguish unsupported functionality, user cancellation, denied access and
operation failure only where the consumer can act on those distinctions.
User cancellation of a platform dialog and cancellation of an owning async task
must not be conflated automatically.

## Compilation and package boundaries

Separate the compiler backend from the execution environment. Native does not
mean Windows, and JS/WasmGC alone does not establish the presence of a browser.
Use module/package target declarations, file-level target selection and
declaration-level platform conditions for the boundary each actually describes.
Verify supported configurations with the pinned compiler, including rejection
of unsupported imports. `preferred_target` selects a default; it is not an OS
compatibility declaration or a runtime permission check.

Keep common contracts independent of hosts. Host adapters implement those
contracts and may depend on lower-level platform packages. Put substantial
Windows-specific mechanisms below the native host when that separation serves
an actual dependency boundary; do not move every file merely to mirror a diagram.

The `capabilities/clock` and `capabilities/http` packages are capabilities/ports,
distinct from reactive effects and the language's async/raise effects. Their
public paths use the capability terminology; no parallel alias packages are
provided. Source consumers updating from the former `effects/clock` and
`effects/http` paths must update their imports with the framework revision.
The contracts and task ownership are unchanged by this rename.

## Ownership and composition

Capabilities do not introduce a scheduler or own unrelated application tasks.
Reuse structured async ownership. The operation/adapter owns resources acquired
for that call; the application/host owns longer-lived resources and disposes them
after work that uses them has ended. Make asynchronous cleanup limitations
explicit rather than equating an abort request with completed cleanup.

Decorators such as TimedHttp may compose capabilities while preserving these
rules. A common failure type contains failures meaningful to that contract's
consumer. Do not add every retry/cache/circuit-breaker implementation detail to
a central Http failure enum; a decorator can expose a separate result contract
when callers need its additional meaning.

Represent deferred commands as data only when a consumer needs that property.
Ordinary waiting, IO or adapter composition does not itself require a global
command interpreter, a service locator or an application-wide resource record.

## Adoption and verification

Adopt small capabilities, explicit environment packages and separate ownership.
Qualify broad Storage/Clipboard commonality by the actual guarantees. Defer
unneeded platform APIs, wholesale folder moves and public-path renaming until
their consumers and migration are concrete.

For each new public resource boundary, establish its success/failure contract,
target/environment support, runtime availability and cleanup owner. Exercise a
real external application operation, controlled error/cancellation cases and
the relevant production adapters. Compile-time exclusions must be tested rather
than inferred from names. A Windows test cannot certify another native OS; a
synthetic browser operation cannot certify physical IME or OS permission UI.

See [application entry](../application-entry.md) for implemented APIs and limits.
Do not interpret this policy as a promise of general file APIs, clipboard
permissions, cross-platform window control or stable long-term API compatibility.
