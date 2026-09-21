///|
pub struct SystemClock {}

///|
pub fn SystemClock::new() -> SystemClock {
  SystemClock::{ }
}

///|
pub impl @capability.Clock for SystemClock with fn now(_) {
  @async.now()
}

///|
pub impl @capability.Clock for SystemClock with fn sleep(_, milliseconds) {
  @capability.validate_delay(milliseconds)
  @async.sleep(milliseconds)
}
