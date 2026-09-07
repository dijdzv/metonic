# Windows event-pump evaluation

The `wzzc-dev/window` candidate at
`b33c9f0ac85002bca4a9cceccbbcd512d13b7ceb` was evaluated on Windows on
2026-09-07 before replacing the existing window/worker boundary.
The candidate sources were not patched. This experiment uses message-loop
callbacks without creating a visible window; it does not exercise real input,
IME, cross-thread wakeup while blocked, or window teardown ordering.

## Observed behavior

Each mode calls `pump_app_events(Some(25), app)` once in a separate process.

| Mode | Return | About-to-wait callbacks | Proxy callbacks |
| --- | --- | --- | --- |
| Wait | Continue | 1 | 0 |
| Poll | Exit(0) | 1000 | 0 |
| WaitUntil | Continue | 1 | 0 |
| Proxy queued before Wait pump | Continue | 2 | 0 |

All four processes exited normally within the parent's five-second deadline.
The Poll callback explicitly requests exit at count 1000. Its return therefore
does not demonstrate that one pump iteration yields to its caller. The proxy
case calls `create_proxy().wake_up()` before pumping but receives no
`proxy_wake_up` callback. It does not test a different thread posting while the
loop is blocked.

WaitUntil uses a fixed timestamp and an explicit 25 ms pump argument. This
checks the selected pump path, not absolute-deadline semantics. Parent elapsed
times include process startup and must not be interpreted as pump latency.

Source inspection agrees with these observations: Windows `run_message_loop`
continues in Poll mode until exit; the proxy posts a thread message with value
`0x8000 + 0x100`, while the C window procedure defines `WM_USER + 0x100`.
The message processing paths translate/dispatch messages without a visible
route to the application proxy callback. Correcting the constant alone would
not establish a complete thread-message dispatch path.

## Reproduction

Complete the [toolchain setup](../development.md). Use a Visual Studio x64
Native Tools command prompt at the repository root, with Git and mise available.
The following commands use `cmd.exe` syntax and a fresh ignored checkout:

```bat
git clone https://github.com/wzzc-dev/window.git .work\window-pump-source
git -C .work\window-pump-source checkout --detach b33c9f0ac85002bca4a9cceccbbcd512d13b7ceb
echo {"private":true,"type":"commonjs"} > .work\window-pump-source\package.json
mkdir .work\window-pump-source\modules\window\examples\metonic_pump_probe
copy experiments\window_pump\main.mbt .work\window-pump-source\modules\window\examples\metonic_pump_probe\main.mbt
copy experiments\window_pump\moon.pkg .work\window-pump-source\modules\window\examples\metonic_pump_probe\moon.pkg
set "MOON_HOME=%CD%\.tools\moonbit"
mise exec -- .tools\moonbit\bin\moon.exe -C .work\window-pump-source\modules\window build examples/metonic_pump_probe --target native --target-dir "%CD%\.work\window-pump-build"
mise exec -- .tools\moonbit\bin\moon.exe run scripts/observe-window-pump.mbtx -- "%CD%\.work\window-pump-build\native\debug\build\wzzc-dev\window\examples\metonic_pump_probe\metonic_pump_probe.exe"
```

The CommonJS boundary prevents the candidate's `build.js` from inheriting the
parent project's ESM setting. The MSVC environment is required both for compiler
selection and the candidate's Windows link flags. Select the package explicitly:
changing only the working directory builds other packages too. Do not import
the candidate's sample `util` package, which includes macOS sources.

The standalone fixture manifest isolates it from the root module. Copy only the
two package files into the pinned candidate workspace as shown; this experiment
does not adopt a registry release in place of that source revision. The observer
reports process failures separately from observed callback counts. A zero
observer exit proves normal process completion, not correct event-loop behavior.
This opt-in candidate evaluation is separate from the normal application gate.

## Decision and remaining work

### Isolated correction contract

`experiments/window_pump_contract/windows-pump.patch` contains a local correction
against the same pinned source revision. It changes only the candidate's Windows
event loop, callback dispatch, FFI declarations and native message helpers. It
does not replace the application's existing window/worker boundary.
The patch includes context from
[`wzzc-dev/window`](https://github.com/wzzc-dev/window/tree/b33c9f0ac85002bca4a9cceccbbcd512d13b7ceb),
licensed under Apache-2.0 (see the repository's [Apache license](../../LICENSE-APACHE)).
The changed behavior described here is a local modification, not an upstream
release or an upstream endorsement.

The correction classifies retrieved thread messages before dispatching window
messages, preserves the `WM_QUIT` exit code and limits each pump cycle to 64
messages, including the first message. A finite wait occurs only before that
drain; subsequent messages are retrieved without waiting. Windows deadlines use
`GetTickCount64` milliseconds. This clock choice is Windows-specific and does not
establish a portable clock contract for the candidate's other platforms.

The separate `window_pump_contract` fixture asserts behavior instead of treating
normal process completion as success. Its cases cover one-cycle Poll return,
two queued proxy notifications without duplicates, a self-replenishing queue,
finite Wait, future and expired deadlines, and preservation of quit code 17.
The cross-process case publishes the receiver's thread ID after queue setup and
posts a notification from a second process. Both processes report timestamps in
the same Windows boot-clock domain so the observer can check that the post occurs
within the receiver's pump call. This is not direct evidence of the internal OS
wait state, worker completion ownership, or window teardown ordering.

To build this fixture, use the setup above in a separate checkout, apply the
patch with `git apply`, and copy only `main.mbt` and `moon.pkg` from
`experiments/window_pump_contract` into
`modules/window/examples/metonic_pump_contract`. Do not copy the standalone
`moon.mod` into the candidate module. Select that example package when building
and use a fresh target directory so cached native objects cannot hide a C change.
The observer is `scripts/verify-window-pump.mbtx` and takes the resulting absolute
executable path. Keep the original checkout available for comparison.

On Windows on 2026-09-07, the corrected candidate passed all seven ordinary cases
and the receiver/sender case; the observer exited 0. Observed values were:

| Contract | Corrected candidate |
| --- | --- |
| Poll | Continue, one about-to-wait callback |
| Queued proxy | Two callbacks, still two after a second pump |
| Replenishing queue | Continue after 64 callbacks |
| Wait 100 ms | Continue after 109 ms |
| Deadline in 100 ms, pump limit 500 ms | Continue after 110 ms |
| Expired deadline | Continue after 0 ms |
| Quit | Exit(17), no about-to-wait callback |
| Separate sender | One callback; post timestamp inside receiver pump interval |

The receiver interval was `[711613843, 711613984]` ms and the sender recorded
`711613984` ms immediately before posting. These are boot-relative timestamps,
not calendar times, and the measurement does not imply a latency guarantee.

The same fixture against the unchanged revision produced observer exit 1: Poll
failed its Continue assertion and quit failed its Exit assertion. Proxy, flood,
Wait, future/past deadline and receiver cases reached their three-second parent
deadlines. Wait/deadline/receiver cases first drain startup through Poll, so these
timeouts do not isolate their subsequent waiting paths. This negative comparison
demonstrates rejection of the unchanged implementation, not independent diagnosis
of every timeout. A missing executable also produced observer exit 1.

Each child uses a three-second deadline, concurrent stdout/stderr drains and a
64 KiB bound per stream. Receiver stdout includes the READY bytes in that bound.
Child processes are joined before their pipe handles are closed, including on
cancellation. Exactly one matching successful RESULT record and a successful
child exit are required; these checks supplement the fixture's assertions.

### Adoption boundary

Keep the current window/worker boundary until equivalent wakeup and bounded-pump
behavior is verified. A minimal correction needs thread-message dispatch to the
application callback and a bounded nonblocking pump contract. Verify queued
completion, wakeup during waiting, shutdown ordering and all control-flow modes
before adoption. Track that work in
[Issue 54](https://github.com/dijdzv/metonic/issues/54); actual OS input and IME
remain separate requirements.
