# Phase 5 external-board measurement

Measured 2026-09-25 on Windows 11 Pro 10.0.26200 x64, Intel i5-13400,
34,121,822,208 bytes RAM, MoonBit `0.1.20260904`, Node `26.8.1` and Chromium
`153.0.8010.12`. The branch started from main `3bdaad9`. The quote-board source
consumer pins Metonic `53352af4d5e8f5327a0e29e5768ad23e5a6b6e76`; the
Notes consumer was updated to pin `3bdaad930028af416231508261e50b3c4b219695`
because its `Application.serials` field cannot compile against its old pin.

Run from `consumers/metonic-quote-board`:

```text
mise run measure:browser
mise run measure:native
```

Both use one warmup and three measured, fresh application instances per target.
The browser runner uses 900×600 headless Chromium, loopback HTTP and SwiftShader.
The native operation runner uses a hidden 760×520 window and the public debug
operation controller, one process per sample because the Windows event loop is
single-use within a process. Each run starts with Amber/JPY, selects Blue, switches
to USD, removes and recreates its detail child, edits the note and waits for its
save acknowledgement. Timings start before the action and end at an observed
state. They include browser automation or native controller dispatch, polling,
rendering and deliberate fixture delays: Blue A/B takes up to 900 ms, D adds
250 ms, C takes 600 ms and a note save takes 800 ms. They are user-flow upper
bounds, **not** pure graph/CPU times. Browser startup ends at host Ready, whereas
initial quote readiness includes the fixture; native initial quote readiness
starts before in-process app creation and includes window startup, but excludes
process launch. Native operation numbers come from a debug build and should not
be compared as release throughput. Each target passed its state assertions and
completed without page errors or probe failure.

Median of the three measured samples, milliseconds:

| Observed step | Browser JS | Browser WasmGC | Native debug |
| --- | ---: | ---: | ---: |
| Host Ready | 384 | 514 | — |
| Initial quote Ready | 1,583 | 1,704 | 1,706 |
| Blue change: pending | 61 | 53 | 56 |
| Blue change: quote Ready | 1,236 | 1,240 | 1,294 |
| USD change: pending | 42 | 49 | 62 |
| USD change: converted quote Ready | 659 | 666 | 708 |
| Detail hidden | 45 | 45 | 28 |
| Detail recreated and quote Ready | 314 | 305 | 326 |
| Note input visible | 51 | 41 | 49 |
| Note save acknowledged | 864 | 858 | 872 |

The browser runner writes all samples, request paths and CDP resource counters
to ignored `verification-output/browser-measurements.json`. Measured JS heap at
the end of the flow was 12,739,852–13,004,244 bytes for JS and
31,848,844–32,110,996 bytes for WasmGC. This is Chromium's JS heap counter,
not total Wasm, GPU or process memory.

The native runner writes each sample to ignored `verification-output/native-measure-*.log`.
It also launches the **release** executable in separate processes using the
existing owned-window acceptance helper and records process resources at window
creation and after its async operations. Three measured post-operation samples
used 230,383,616–230,645,760 working-set bytes,
408,858,624–411,348,992 private bytes and 645 handles. Each process closed its
window and reported `GPU_OWNERSHIP_RELEASED` and `WINDOW_CLEANUP_OK`. These
process counters do not measure GPU residency; the final numeric sample precedes
shutdown. The native debug controller's resource counters are kept separate
from these release-process observations.

## Release size

The browser runner records each file's raw length and independent gzip level-6
length in ignored `verification-output/browser-size.json`. Its request list is
the set fetched by the measured page; the loopback server actually sent
uncompressed bytes, so the gzip column is a **transfer estimate** if those
same files were served with gzip, with an empty cache and no HTTP framing.
Neither backend fetched the other backend's application artifact or the
packaged license files during this flow.

| Browser file group | Raw bytes | gzip bytes |
| --- | ---: | ---: |
| Application JS | 6,260,481 | 667,828 |
| Application WasmGC | 1,930,622 | 604,176 |
| Shared host JavaScript | 53,400 | 10,532 |
| Noto Sans JP font | 9,589,900 | 5,874,995 |
| Requested files, JS path | 15,904,632 | 6,553,880 |
| Requested files, WasmGC path | 11,574,773 | 6,490,228 |

The requested-path rows include `index.html` (851 raw / 525 gzip bytes) in
addition to the app, shared host and font. They count each URL once. The font
dominates both transfer estimates. `mise run browser:build` at this branch also
produced the smaller two-Source async-pair comparison: `async-pair.mjs` was
6,128,425 bytes and `async-pair.wasm` was 1,891,690 bytes uncompressed. The
quote board adds 132,056 and 38,932 bytes respectively. This is a small
framework application comparator, not a claim about the minimum possible
MoonBit output or an identical feature set.

`package-native.mbtx` produced a 26-file Windows release inventory from the
pinned consumer. Its listed payload files total 23,707,139 raw bytes, excluding
the generated inventory JSON itself: `QuoteBoard.exe` 13,446,656,
`accesskit.dll` 354,304, font and font license 9,594,288, third-party/project
notices 310,020, and `DISTRIBUTION.md` 1,871. The package remains reproducible
from its source and toolchain pin; it is not a published binary release.

## Existing baselines and regressions

The fixed 100,000-write synchronous graph benchmark was rerun with the original
warmup/three-measurement method and checksums: native 39/39/38 ms, JS 73/61/58
ms, WasmGC 13/12/12 ms. The [pre-async record](reactive-phase4-baseline.md)
was 36/34/34, 68/58/53 and 11/12/11 ms. These short integer-ms samples and
runtime/JIT variation do not establish a material speed change; no threshold
was relaxed.

After repinning Notes to the integrated public contract, the **unchanged**
frozen 1,000-memo browser JS/WasmGC and native operation runners each passed
one warmup plus three measured runs. Their runners enforce every existing
per-sample latency, row-count, browser heap and native probe limit from
[#501](https://github.com/dijdzv/metonic/issues/501). The separate native
release resource runner passed its fixed 300 MiB working-set, 512 MiB private-use
and 800-handle limits at every checkpoint in all three measured samples; the
largest observed measured working set was 241,999,872 bytes, private use
420,102,144 bytes and handle count 665. The existing GPU lifetime assertions
passed on browser Stop and native close. Detailed local results remain ignored
under `consumers/metonic-notes/.work/scale/`.

Notes browser editing, collection persistence/recovery, autosave, MCP and CLI
attach/detach passed on JS and WasmGC. Native MCP edit/save/reconnect, isolated
storage, save/restore and release close passed. Browser and native package checks
passed unrelated-directory operation and production exclusion. None of these
synthetic checks is physical IME verification. Reproduce with the Notes consumer
tasks `verify:browser`, `verify:native-control`, `verify:persistence`,
`verify:browser-package`, `verify:native-package`, `scale:baseline-browser`,
`scale:baseline-native` and `scale:resources-native`.

## Final first-group integration check

On 2026-09-26, both independent consumers were repinned to integrated Metonic
`c4a9bf6d05006b40b5f259547b29e0b8beeb12b6` after the owned Status and
first-group theme/gallery changes. This section is a new measurement, not a
replacement for the historical baseline above. The quote board's model tests
passed 18/18 on JS and native; browser JS/WasmGC and native operation checks
passed without application-side behavior changes. Its native measurement helper
had to stop selecting status text by the position of controls without a semantic
reference: owned Status controls now have one. It selects the existing display
row by geometry and buttons by name; the measured action sequence and limits
are unchanged. The Notes consumer, which constructs `Application` directly and
uses its own controls, added `components: None` for the new public field. Its
56 JS and 20 WasmGC model tests then passed.

The same quote-board warmup and three measured flows passed on all three
targets. Median step times in milliseconds:

| Observed step | Browser JS | Browser WasmGC | Native debug |
| --- | ---: | ---: | ---: |
| Host Ready | 380 | 552 | — |
| Initial quote Ready | 1,583 | 1,722 | 1,680 |
| Blue change: pending | 63 | 55 | 45 |
| Blue change: quote Ready | 1,247 | 1,240 | 1,262 |
| USD change: pending | 47 | 51 | 44 |
| USD change: converted quote Ready | 658 | 661 | 675 |
| Detail hidden | 49 | 35 | 23 |
| Detail recreated and quote Ready | 304 | 312 | 310 |
| Note input visible | 50 | 39 | 32 |
| Note save acknowledged | 867 | 859 | 860 |

These times include the same deliberate fixture delays and automation overhead
described above. No fixed operation limit was relaxed. Measured end-of-flow
Chromium JS heap was 14,335,696–15,116,900 bytes for JS and
22,089,344–32,436,620 bytes for WasmGC; this counter does not include all
process or GPU memory. The three native release-process post-operation samples
used 233,222,144–237,817,856 working-set bytes,
410,316,800–415,113,216 private bytes and 624 handles, then closed with GPU
ownership released. Native debug operation measurements and release resource
measurements remain separate.

Release payload sizes from this pin:

| Browser file group | Raw bytes | gzip bytes |
| --- | ---: | ---: |
| Application JS | 6,969,203 | 750,725 |
| Application WasmGC | 2,131,399 | 665,644 |
| Shared host JavaScript | 54,440 | 10,632 |
| Noto Sans JP font | 9,589,900 | 5,874,995 |
| Requested files, JS path | 16,614,394 | 6,636,877 |
| Requested files, WasmGC path | 11,776,590 | 6,551,796 |

The browser requested-path rows include `index.html` and exclude unfetched
licenses. They are gzip level-6 estimates, not observed compressed transfer.
The native 26-file package totals 24,027,139 payload bytes excluding its
inventory JSON, including `QuoteBoard.exe` at 13,766,656 bytes. Against the
earlier record, application JS increased 708,722 raw bytes, WasmGC increased
200,777, and the native executable increased 320,000. This interval also
contains the owned component, status and theme work; it is not a measured
per-feature size allocation. Both package verifiers passed browser JS/WasmGC,
native unrelated-directory launch and close, inventory and license checks,
development-feature exclusion and overwrite protection.

Notes browser JS/WasmGC editing, persistence, search, dynamic list, autosave,
CLI and MCP checks passed. Native MCP, persisted storage, save/restore and
package relocation passed. Its fixed 1,000-memo browser and native operation
sequences each passed one warmup and three measured runs under the existing
per-sample limits. The native release resource run also passed all limits; the
largest measured checkpoint was 241,991,680 working-set bytes,
421,302,272 private bytes and 665 handles. The unchanged 100,000-write graph
benchmark returned checksums 300001/500001/700001 on all targets, with
native 33/34/33 ms, JS 61/56/52 ms and WasmGC 10/11/10 ms. These short
integer-millisecond samples do not establish a material speed difference.
Physical IME input remains outside these synthetic checks.
