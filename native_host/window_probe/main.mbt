///|
async fn main {
  let mode = @env.get_env_var("METONIC_WINDOW_INIT_TEST").unwrap_or("normal")
  require(
    mode == "normal" || mode == "input" || mode == "close",
    "unknown initialization test",
  )
  let scenario : Scenario = {
    mode,
    retained: false,
    polls: 0,
    stage: 0,
    canceled_id: 0,
  }
  @ui.run(
    observer=Some(view => scenario.step(view)),
    completed=Some(view => scenario.finish(mode, view)),
    hidden=true,
    lifecycle=Some((phase, view) => scenario.lifecycle(phase, view)),
  )
}
