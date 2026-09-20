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
pub async fn get_user(base : String, id : String) -> Result[@api.User, String] {
  @user_load.load(
    @timed.TimedHttp::{
      transport: @transport.NativeHttp::{ base, },
      clock: SystemClock::{ },
      milliseconds: 3000,
    },
    id,
  )
}
