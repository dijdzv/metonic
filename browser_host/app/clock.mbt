///|
priv struct BrowserClock {
  wake : @cond_var.Cond
  mut timer : Int?
  mut reset : Bool
  mut ready : Bool
}

///|
priv suberror ClockReset

///|
impl @clock.Clock for BrowserClock with fn now(_) {
  @async.now()
}

///|
impl @clock.Clock for BrowserClock with fn sleep(self, milliseconds) {
  @clock.validate_delay(milliseconds)
  self.timer = Some(
    host_set_timeout(
      fn() {
        self.ready = true
        // A host callback is outside async's scheduler; signaling alone cannot drain it.
        @async.run_async_main(() => self.wake.signal())
      },
      milliseconds,
    ),
  )
  defer (if self.timer is Some(timer) {
    host_clear_timeout(timer)
    self.timer = None
  })
  while !self.ready && !self.reset {
    self.wake.wait()
  }
  if self.reset {
    raise ClockReset
  }
}

///|
fn BrowserClock::cancel(self : BrowserClock) -> Unit {
  self.reset = true
  if self.timer is Some(timer) {
    host_clear_timeout(timer)
    self.timer = None
  }
  @async.run_async_main(() => self.wake.signal())
}
