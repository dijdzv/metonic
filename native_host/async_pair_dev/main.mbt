///|
async fn main {
  let clock = @production_clock.SystemClock::new()
  let diagnostics = @reactive_task.TraceRegistry::new(32)
  let app = @pair.create(
    milliseconds => @clock.Clock::sleep(clock, milliseconds),
    diagnostics=Some(diagnostics),
  )
  @window_host.run(
    @host.from_application(app),
    hidden=true,
    controller=Some(@application_control.control),
    diagnostics=Some(diagnostics),
  )
}
