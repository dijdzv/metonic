///|
fn status(app : @app.Application) -> String {
  (app.view)()[5].element.text
}

///|
async fn wait_status(app : @app.Application, expected : String) -> Unit {
  @async.with_timeout(5000, () => {
    while status(app) != expected {
      @async.sleep(20)
    }
  })
}

///|
async fn main {
  let clock = @production_clock.SystemClock::new()
  let diagnostics = @reactive_task.TraceRegistry::new(32)
  let app = @pair.create(
    milliseconds => @clock.Clock::sleep(clock, milliseconds),
    diagnostics=Some(diagnostics),
  )
  let two = (app.view)()[1].element.reference.unwrap()
  let retry = (app.view)()[3].element.reference.unwrap()
  let refresh = (app.view)()[2].element.reference.unwrap()
  let cancel = (app.view)()[4].element.reference.unwrap()
  let completed = Ref(false)
  @window_host.run(
    @host.from_application(app),
    hidden=true,
    controller=Some(handle => {
      @async.with_timeout(15000, async fn() {
        wait_status(app, "Ready one: Detail one / Related one")
        let first_trace = (handle.inspect)().diagnostics.unwrap()
        assert_eq(diagnostics.sources().length(), 2)
        assert_eq(diagnostics.derived().length(), 1)
        assert_eq(diagnostics.derived()[0].phase, "ready")
        assert_true(first_trace.stringify().contains("\"sources\""))
        assert_false(first_trace.stringify().contains("Detail one"))
        let ready = (handle.capture)(_ => ())
        assert_eq(ready.pixels.length(), ready.width * ready.height * 4)
        assert_eq(
          (handle.operate)(
            two, @window_host.ActivateControl, (handle.inspect)().semantic_revision,
          ),
          "",
        )
        assert_eq(status(app), "Loading two")
        let loading = (handle.capture)(_ => ())
        assert_true(loading.pixels != ready.pixels)
        wait_status(app, "Failed two: related data unavailable")
        let failed_trace = (handle.inspect)().diagnostics.unwrap()
        assert_true(failed_trace.stringify().contains("\"kind\":\"expected_failure\""))
        assert_false(failed_trace.stringify().contains("related data unavailable"))
        let failed = (handle.capture)(_ => ())
        assert_true(failed.pixels != loading.pixels)
        assert_eq(
          (handle.operate)(
            retry, @window_host.ActivateControl, (handle.inspect)().semantic_revision,
          ),
          "",
        )
        wait_status(app, "Ready two: Detail two / Related two")
        let retried = (handle.capture)(_ => ())
        assert_true(retried.pixels != failed.pixels)
        assert_eq(
          (handle.operate)(
            refresh, @window_host.ActivateControl, (handle.inspect)().semantic_revision,
          ),
          "",
        )
        assert_eq(status(app), "Refreshing two: Detail two / Related two")
        let joined_before = diagnostics.events().filter(event => {
          event.kind == @reactive_task.CleanupJoined
        }).length()
        assert_eq(
          (handle.operate)(
            cancel, @window_host.ActivateControl, (handle.inspect)().semantic_revision,
          ),
          "",
        )
        assert_eq(status(app), "Canceled two")
        @async.with_timeout(5000, () => {
          while diagnostics.events().filter(event => {
              event.kind == @reactive_task.CleanupJoined
            }).length() <= joined_before {
            @async.sleep(20)
          }
        })
        assert_true(diagnostics.events().any(event => {
          event.kind == @reactive_task.CancellationRequested
        }))
        completed.val = true
        (handle.apply)(@window_host.Close)
      })
    }),
    diagnostics=Some(diagnostics),
  )
  assert_true(completed.val)
  println("NATIVE_ASYNC_PAIR_DISPLAY_OK")
}
