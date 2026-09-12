///|
async fn main {
  let mode = @env.get_env_var("METONIC_WINDOW_INIT_TEST").unwrap_or("normal")
  if mode == "query" || mode == "query-latin" {
    let scenario : QueryScenario = {
      stage: 0,
      original: None,
      polls: 0,
      text: if mode == "query" {
        "日本語日本語 日本語日本語 日本語日本語 日本語日本語"
      } else {
        "abcdefghij abcdefghij abcdefghij abcdefghij abcdefghij"
      },
      expected: "",
    }
    @ui.run(
      observer=Some(view => scenario.step(view)),
      completed=Some(_ => assert_eq(scenario.stage, 12)),
      hidden=true,
    )
    return
  }
  if mode == "capture" {
    @ui.run(controller=Some(capture_observation), hidden=true)
    return
  }
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
    scene_revision: 0,
    precomposition_run: 0UL,
  }
  @ui.run(
    observer=Some(view => scenario.step(view)),
    completed=Some(view => scenario.finish(mode, view)),
    hidden=true,
    lifecycle=Some((phase, view) => scenario.lifecycle(phase, view)),
  )
}
