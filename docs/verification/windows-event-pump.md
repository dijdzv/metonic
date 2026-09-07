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

Keep the current window/worker boundary until equivalent wakeup and bounded-pump
behavior is verified. A minimal correction needs thread-message dispatch to the
application callback and a bounded nonblocking pump contract. Verify queued
completion, wakeup during waiting, shutdown ordering and all control-flow modes
before adoption. Track that work in
[Issue 54](https://github.com/dijdzv/metonic/issues/54); actual OS input and IME
remain separate requirements.
