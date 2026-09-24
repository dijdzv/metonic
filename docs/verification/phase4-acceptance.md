# Phase 4 initial usable scope: acceptance record

Status: accepted for the bounded scope below on 2026-09-25. This is a source
and package acceptance record, not an announced version tag or a production
support guarantee.

## Supported path

An external MoonBit application can use Metonic's pinned source entry and
application-facing packages to build a Windows x64 native UI and a WebGPU
browser UI using WasmGC. Browser JS compiles the same application for comparison
and regression checks; it also renders through WebGPU, not a DOM renderer. Both
browser outputs use DOM elements for input and semantics. The tracked independent
[Memo consumer](../../consumers/metonic-notes/README.md) declares an ESM package
scope and pins the verified framework revision. The [application entry](../application-entry.md)
describes the public boundary and its current limits.

The state and lifetime boundary is exercised by reactive UI, editing, save and
restore, close decisions, and asynchronous work in Memo. The separate
[two-host asynchronous example](async-pair-phase4.md) checks independent results,
pending and refresh states, failure, cancellation, replacement and Scope
disposal without copying host internals. The pinned [structural checker](static-analysis.md)
parses MoonBit source fail-closed and enforces an established boundary rule.

## Verification

- [Clean Windows CI on the final ESM consumer change](https://github.com/dijdzv/metonic/actions/runs/36013320767)
  passed browser JS/WasmGC, headless WebGPU, native source/window, async,
  accessibility, static analysis and development-artifact exclusion checks.
- The integrated revision passed all 29 local pre-commit and all 29 pre-push
  checks before [#582](https://github.com/dijdzv/metonic/pull/582). The later
  release-contract correction [#583](https://github.com/dijdzv/metonic/pull/583)
  passed the same local gates. The independent ESM consumer passed native and
  browser builds and behavior checks, its source contract and a disposable
  first-setup test. The [ESM evidence](external-esm-consumer.md) distinguishes
  this path from an upstream GPU-library fix.
- On 2026-09-25, the independent consumer's browser and native package checks,
  native persistence check, and fixed 1,000-memo browser JS/WasmGC and native
  operation and resource checks all passed. These are reproducible through its
  `verify:browser-package`, `verify:native-package`, `verify:persistence`,
  `scale:baseline-browser`, `scale:baseline-native` and
  `scale:resources-native` mise tasks. One warmup and three measured runs passed
  for each fixed-size scenario. Detailed measurements stay in ignored local
  output; the [consumer instructions](../../consumers/metonic-notes/README.md#tested-collection-size)
  give the thresholds and hardware scope.
- Recorded real Windows IME and bounded Narrator observations remain separate
  from synthetic input and headless checks; see the [native input acceptance](../../consumers/metonic-notes/README.md#physical-native-input-acceptance)
  and [initial verification index](p0.md). No new physical IME claim follows
  from these automated runs.

## Limits and follow-up

This evidence covers the tested Windows x64 native environment and Chromium
WebGPU path. It does not establish clean-machine installation, every GPU or
browser, every IME or assistive client, concurrent browser-tab storage, cloud
sync, an unlimited collection or a stable API across unpinned revisions. The
[release criteria](../initial-release-criteria.md) list input, storage, task
and feature limits. The published GPU library still has a CommonJS prebuild
scope defect [#453](https://github.com/dijdzv/metonic/issues/453); Metonic's
source entry isolates that dependency for ESM consumers without editing the
published package. A fixed upstream version should replace the temporary
boundary after separate verification. Open P2/P3 Issues are subsequent or
conditional work, not silently considered solved by this acceptance record.
