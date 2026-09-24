# Reactive graph baseline before async-derived-state integration

Recorded on 2026-09-24 before adding Phase 4 async-derived-state behavior.
This is a baseline for [#567](https://github.com/dijdzv/metonic/issues/567),
not a release performance guarantee.

`tools/benchmark_reactive` constructs a fresh Graph and Scope, one Signal, one
Memo that doubles the Signal, and one Binding that records the observed value and
notification count. It warms up once, then measures three separate runs of
100,000 changing Signal writes. Each timed run creates its own Graph. The
checksum confirms the final derived value and 100,001 Binding notifications
(including the initial application); it prevents the observable path from being
discarded. `@async.now()` is sampled outside the update loop and reported at
integer-millisecond resolution.

Run sequentially on the pinned toolchain:

```text
mise exec -- .tools/moonbit/bin/moon.exe run tools/benchmark_reactive --target native --release --deny-warn
mise exec -- .tools/moonbit/bin/moon.exe run tools/benchmark_reactive --target js --release --deny-warn
mise exec -- .tools/moonbit/bin/moon.exe run tools/benchmark_reactive --target wasm-gc --release --deny-warn
```

| Target | Three measured runs for 100,000 updates |
| --- | --- |
| Native | 36, 34, 34 ms |
| JS | 68, 58, 53 ms |
| WasmGC | 11, 12, 11 ms |

All commands exited zero with warnings denied and the expected checksums
`300001`, `500001`, `700001`. The host was Windows 11 Pro 10.0.26200 x64 with
an Intel i5-13400 and 31.8 GiB RAM. JS and WasmGC ran through `moon run`, not
inside a browser. The pinned Moon tool was `0.1.20260904` and Node was `26.8.1`.
Startup and compilation are outside the timed loop. The JS
times include JIT effects; the integer clock and single short sample do not
justify fine-grained backend rankings or a speedup claim. This scenario has no
input, DOM, GPU, async work or storage.

The separate [Notes 1,000-memo scenario](../../consumers/metonic-notes/README.md#tested-collection-size)
is the integrated input-response and resource baseline. Its fixed search,
selection, edit, scroll, save and startup checks were measured on the same host
for native and headless browser JS/WasmGC before Phase 4 changes. Compare both
the graph microbenchmark and the integrated scenario after changing the graph
or binding path; the first cannot substitute for the second.
