///|
extern "C" fn wake() -> Unit = "metonic_async_wake"

///|
extern "C" fn init_ui_thread() -> Unit = "metonic_async_init_ui_thread"

///|
extern "C" fn wake_count() -> Int = "metonic_async_wake_count"

///|
extern "C" fn failed_wake_count() -> Int = "metonic_async_failed_wake_count"

///|
extern "C" fn is_window(hwnd : UInt64) -> Int = "IsWindow"

///|
struct Probe {
  event_loop : @windows.EventLoop
  mut zero_count : Int
  mut finite_count : Int
  mut indefinite_count : Int
  mut proxy_count : Int
  mut main_done : Bool
  mut pending : Int
  mut cleanup : Int
  mut completed : Int
  mut io_wakes : Int
  mut io_proxies : Int
  mut io_indefinite : Int
  mut timer_ms : Int64
  mut shutdown_ms : Int64
  mut window : @windows.Window?
  mut hwnd : UInt64
}

///|
fn Probe::new(event_loop : @windows.EventLoop) -> Probe {
  {
    event_loop,
    zero_count: 0,
    finite_count: 0,
    indefinite_count: 0,
    proxy_count: 0,
    main_done: false,
    pending: 0,
    cleanup: 0,
    completed: 0,
    io_wakes: 0,
    io_proxies: 0,
    io_indefinite: 0,
    timer_ms: 0L,
    shutdown_ms: 0L,
    window: None,
    hwnd: 0UL,
  }
}

///|
pub impl @windows.ApplicationHandler for Probe with fn can_create_surfaces(
  self,
  event_loop,
) {
  let attrs = @core.WindowAttributes::default().with_visible(false)
  let window = event_loop.create_window(attrs)
  self.hwnd = window.native_window_handle()
  self.window = Some(window)
}

///|
pub impl @windows.ApplicationHandler for Probe with fn proxy_wake_up(
  self,
  _event_loop,
) {
  self.proxy_count += 1
}

///|
pub impl @windows.ApplicationHandler for Probe with fn about_to_wait(
  _self,
  _event_loop,
) {
  ()
}

///|
using @external_loop_integration {trait ExternalEventLoop}

///|
pub impl ExternalEventLoop for Probe with fn poll(self, timeout?) {
  match timeout {
    Some(0) => self.zero_count += 1
    Some(_) => self.finite_count += 1
    None => self.indefinite_count += 1
  }
  match self.event_loop.pump_app_events(timeout, self) {
    @core.PumpStatus::Continue => ()
    @core.PumpStatus::Exit(_) => abort("external event loop exited")
  }
}

///|
pub impl ExternalEventLoop for Probe with fn get_wakeup_callback_for_foreign_thread(
  _self,
) {
  () => wake()
}

///|
pub impl ExternalEventLoop for Probe with fn terminate(self) {
  require(self.main_done, "terminate before async main")
  require(self.pending == 0, "pending tasks remain")
  require(wake_count() > 0, "no foreign wake")
  require(failed_wake_count() == 0, "foreign wake failed")
  require(self.proxy_count > 0, "no proxy callback")
  require(self.finite_count > 0, "no finite poll")
  require(self.zero_count > 0, "no zero poll")
  require(self.indefinite_count > 0, "no indefinite poll")
  match self.window {
    Some(window) => {
      window.drop()
      self.window = None
      require(is_window(self.hwnd) == 0, "hidden window survived drop")
    }
    None => abort("missing hidden window")
  }
  let line = "RESULT {\"ok\":true,\"mode\":\"async\",\"pending\":" +
    self.pending.to_string() +
    ",\"cleanup\":" +
    self.cleanup.to_string() +
    ",\"wakes\":" +
    wake_count().to_string() +
    ",\"proxies\":" +
    self.proxy_count.to_string() +
    ",\"finite\":" +
    self.finite_count.to_string() +
    ",\"zero\":" +
    self.zero_count.to_string() +
    ",\"indefinite\":" +
    self.indefinite_count.to_string() +
    ",\"io_wakes\":" +
    self.io_wakes.to_string() +
    ",\"io_proxies\":" +
    self.io_proxies.to_string() +
    ",\"io_indefinite\":" +
    self.io_indefinite.to_string() +
    ",\"timer_ms\":" +
    self.timer_ms.to_string() +
    ",\"shutdown_ms\":" +
    self.shutdown_ms.to_string() +
    ",\"hwnd_destroyed\":true}"
  println(line)
}

///|
fn require(value : Bool, message : String) -> Unit {
  if !value {
    abort(message)
  }
}

///|
async fn main {
  let args = @env.args()
  guard args.length() == 2 else {
    abort("usage: metonic_async_contract ABSOLUTE_INPUT")
  }
  let event_loop = @windows.EventLoop::new()
  let probe = Probe::new(event_loop)
  init_ui_thread()
  @async.set_external_event_loop(probe)
  probe.event_loop.set_control_flow(@core.ControlFlow::Wait)
  @external_loop_integration.ExternalEventLoop::poll(probe, timeout=0)
  match probe.window {
    Some(_) => ()
    None => abort("hidden window was not created")
  }
  let content = @fs.read_file(args[1]).text()
  require(content == "metonic async wake\n", "unexpected input sentinel")
  probe.io_wakes = wake_count()
  probe.io_proxies = probe.proxy_count
  probe.io_indefinite = probe.indefinite_count
  require(probe.io_wakes > 0, "I/O did not produce foreign wake")
  require(probe.io_proxies > 0, "I/O did not produce proxy callback")
  require(probe.io_indefinite > 0, "I/O did not use indefinite poll")
  let start = @async.now()
  @async.sleep(100)
  let elapsed = @async.now() - start
  require(elapsed >= 80L && elapsed <= 1000L, "timer elapsed")
  probe.timer_ms = elapsed
  let mut cancel_start = 0L
  @async.with_task_group <| group => {
    let tasks : Array[@async.Task[Unit]] = []
    for _ in 0..<16 {
      let task = group.spawn() <| () => {
        probe.pending += 1
        defer {
          probe.pending -= 1
          probe.cleanup += 1
        }
        @async.sleep(5000)
        probe.completed += 1
      }
      tasks.push(task)
    }
    while probe.pending < 16 {
      @async.pause()
    }
    cancel_start = @async.now()
    for task in tasks {
      task.cancel()
    }
  }
  probe.shutdown_ms = @async.now() - cancel_start
  require(probe.shutdown_ms < 1000L, "task shutdown exceeded 1s")
  require(probe.pending == 0, "cancelled tasks pending")
  require(probe.cleanup == 16, "cancelled task cleanup")
  require(probe.completed == 0, "long task completed normally")
  probe.main_done = true
}
