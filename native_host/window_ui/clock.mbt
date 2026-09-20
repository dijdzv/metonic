///|
priv struct RealClock {}

///|
impl @clock.Clock for RealClock with fn now(_) {
  @async.now()
}

///|
impl @clock.Clock for RealClock with fn sleep(_, milliseconds) {
  @clock.validate_delay(milliseconds)
  @async.sleep(milliseconds)
}
