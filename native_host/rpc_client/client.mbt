///|
pub async fn get_user(base : String, id : String) -> Result[@api.User, String] {
  @user_load.load(
    @timed.TimedHttp::{
      transport: @transport.NativeHttp::{ base, },
      clock: @production_clock.SystemClock::new(),
      milliseconds: 3000,
    },
    id,
  )
}
