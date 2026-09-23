///|
pub(all) suberror InvalidTime

///|
pub fn validate_delay(milliseconds : Int) -> Unit raise InvalidTime {
  if milliseconds < 0 {
    raise InvalidTime
  }
}

///|
pub(open) trait Clock {
  fn now(Self) -> Int64
  async fn sleep(Self, Int) -> Unit
}

///|
pub async fn[C : Clock, A] after(clock : C, milliseconds : Int, value : A) -> A {
  validate_delay(milliseconds)
  clock.sleep(milliseconds)
  value
}
