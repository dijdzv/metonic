///|
priv struct SystemClock {}

///|
impl @clock.Clock for SystemClock with fn now(_) {
  @async.now()
}

///|
impl @clock.Clock for SystemClock with fn sleep(_, milliseconds) {
  @clock.validate_delay(milliseconds)
  @async.sleep(milliseconds)
}

///|
pub using @sample {movement_result}

///|
pub fn movement(model : @application.Model) -> @task.Request {
  @sample.movement(model, SystemClock::{ })
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
      clock: SystemClock::{ },
      milliseconds: 3000,
    },
    value,
  )
}

///|
pub using @sample {cancel}
