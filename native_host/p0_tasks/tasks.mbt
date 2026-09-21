///|
pub using @sample {movement_result}

///|
pub fn movement(model : @application.Model) -> @task.Request {
  @sample.movement(model, @production_clock.SystemClock::new())
}

///|
pub fn user(model : @application.Model, value : String) -> @task.Request {
  @sample.user(
    model,
    @timed.TimedHttp::{
      transport: @transport.NativeHttp::{
        base: @env.get_env_var("METONIC_RPC_BASE").unwrap_or(
          "http://127.0.0.1:4174",
        ),
      },
      clock: @production_clock.SystemClock::new(),
      milliseconds: 3000,
    },
    value,
  )
}

///|
pub using @sample {cancel}
