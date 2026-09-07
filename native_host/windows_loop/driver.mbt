///|
extern "C" fn wake() -> Unit = "metonic_async_wake"

///|
extern "C" fn init_ui_thread() -> Unit = "metonic_async_init_ui_thread"

///|
extern "C" fn wake_count() -> Int = "metonic_async_wake_count"

///|
extern "C" fn failed_wake_count() -> Int = "metonic_async_failed_wake_count"

///|
extern "C" fn message_window() -> UInt64 = "metonic_async_message_window"

///|
pub struct Snapshot {
  zero_count : Int
  finite_count : Int
  indefinite_count : Int
  wakes : Int
  failed_wakes : Int
}

///|
suberror DriverFailure {
  Failure(String)
} derive(Debug)

///|
pub struct Driver {
  event_loop : @windows.EventLoop
  handler : &@windows.ApplicationHandler
  on_terminate : (Snapshot) -> Unit raise Error
  mut zero_count : Int
  mut finite_count : Int
  mut indefinite_count : Int
}

///|
pub fn Driver::new(
  event_loop : @windows.EventLoop,
  handler : &@windows.ApplicationHandler,
  on_terminate : (Snapshot) -> Unit raise Error,
) -> Driver {
  init_ui_thread()
  {
    event_loop,
    handler,
    on_terminate,
    zero_count: 0,
    finite_count: 0,
    indefinite_count: 0,
  }
}

///|
pub fn Driver::snapshot(self : Driver) -> Snapshot {
  {
    zero_count: self.zero_count,
    finite_count: self.finite_count,
    indefinite_count: self.indefinite_count,
    wakes: wake_count(),
    failed_wakes: failed_wake_count(),
  }
}

///|
pub fn Driver::message_window_handle(self : Driver) -> UInt64 {
  let _ = self
  message_window()
}

///|
using @external_loop_integration {trait ExternalEventLoop}

///|
pub impl ExternalEventLoop for Driver with fn poll(self, timeout?) {
  match timeout {
    Some(0) => self.zero_count += 1
    Some(_) => self.finite_count += 1
    None => self.indefinite_count += 1
  }
  match self.event_loop.pump_app_events(timeout, self.handler) {
    @core.PumpStatus::Continue => ()
    @core.PumpStatus::Exit(code) =>
      raise DriverFailure::Failure(
        "external event loop exited with code " + code.to_string(),
      )
  }
}

///|
pub impl ExternalEventLoop for Driver with fn get_wakeup_callback_for_foreign_thread(
  _self,
) {
  () => wake()
}

///|
pub impl ExternalEventLoop for Driver with fn terminate(self) {
  (self.on_terminate)(self.snapshot())
}
