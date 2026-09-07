///|
extern "C" fn get_tick_count64() -> UInt64 = "GetTickCount64"
extern "C" fn get_current_thread_id() -> UInt = "GetCurrentThreadId"
extern "C" fn post_thread_message(thread_id : UInt, message : UInt, wparam : UInt64, lparam : Int64) -> Int = "PostThreadMessageW"
extern "C" fn post_quit_message(code : Int) -> Unit = "PostQuitMessage"
extern "C" fn flush_stdout(stream : UInt64) -> Int = "fflush"

///|
struct Probe {
  mut proxy_count : Int
  mut about_count : Int
  mode : String
  mut proxy : @windows.EventLoopProxy?
}

///|
fn Probe::new(mode : String) -> Probe {
  { proxy_count: 0, about_count: 0, mode, proxy: None }
}

///|
pub impl @windows.ApplicationHandler for Probe with fn proxy_wake_up(self, _event_loop) {
  self.proxy_count += 1
  if self.mode == "flood" && self.proxy_count < 1000 {
    match self.proxy {
      Some(proxy) => proxy.wake_up()
      None => ()
    }
  }
}

///|
pub impl @windows.ApplicationHandler for Probe with fn about_to_wait(self, event_loop) {
  self.about_count += 1
  if self.mode == "poll" && self.about_count >= 1000 {
    event_loop.exit()
  }
}

///|
fn output(line : String) -> Unit {
  println(line)
  ignore(flush_stdout(0))
}

///|
fn startup_drain(event_loop : @windows.EventLoop, app : Probe) -> Unit {
  event_loop.set_control_flow(@core.ControlFlow::Poll)
  ignore(event_loop.pump_app_events(Some(0), app))
  app.proxy_count = 0
  app.about_count = 0
}

///|
fn run(mode : String) -> Unit {
  let event_loop = @windows.EventLoop::new()
  let app = Probe::new(mode)
  if mode == "proxy" || mode == "flood" {
    event_loop.set_control_flow(@core.ControlFlow::Poll)
    let proxy = event_loop.create_proxy()
    app.proxy = Some(proxy)
    proxy.wake_up()
    if mode == "proxy" { proxy.wake_up() }
  }
  if mode == "quit" { post_quit_message(17) }
  if mode == "wait" || mode == "deadline" || mode == "past" {
    startup_drain(event_loop, app)
  }
  let start = get_tick_count64()
  let status = if mode == "poll" {
    event_loop.set_control_flow(@core.ControlFlow::Poll)
    let first = event_loop.pump_app_events(Some(0), app)
    match first {
      @core.PumpStatus::Continue => ()
      _ => abort("poll first pump must continue")
    }
    require(app.about_count == 1, "poll first pump about_to_wait")
    require(app.about_count <= 1000, "poll about_to_wait runaway")
    first
  } else if mode == "proxy" {
    let first = event_loop.pump_app_events(Some(0), app)
    require(first == @core.PumpStatus::Continue, "proxy first pump")
    require(app.proxy_count == 2, "proxy wake count")
    let second = event_loop.pump_app_events(Some(0), app)
    require(second == @core.PumpStatus::Continue, "proxy second pump")
    require(app.proxy_count == 2, "proxy wake count stable")
    second
  } else if mode == "flood" {
    let first = event_loop.pump_app_events(Some(0), app)
    require(first == @core.PumpStatus::Continue, "flood first pump")
    require(app.proxy_count >= 1 && app.proxy_count <= 64, "flood wake count")
    first
  } else if mode == "quit" {
    event_loop.pump_app_events(Some(0), app)
  } else {
    if mode == "deadline" {
      event_loop.set_control_flow(@core.ControlFlow::wait_until(start.reinterpret_as_int64() + 100L))
      event_loop.pump_app_events(Some(500), app)
    } else if mode == "past" {
      event_loop.set_control_flow(@core.ControlFlow::wait_until(start.reinterpret_as_int64() - 1L))
      event_loop.pump_app_events(Some(500), app)
    } else {
      event_loop.set_control_flow(@core.ControlFlow::Wait)
      event_loop.pump_app_events(Some(100), app)
    }
  }
  let elapsed = get_tick_count64() - start
  if mode == "quit" {
    match status {
      @core.PumpStatus::Exit(code) => require(code == 17, "quit code")
      _ => abort("quit must exit")
    }
  } else if mode != "poll" {
    require(status == @core.PumpStatus::Continue, "pump must continue")
  }
  if mode == "wait" { require(elapsed >= 80 && elapsed <= 1000, "wait elapsed") }
  if mode == "deadline" { require(elapsed >= 80 && elapsed <= 400, "deadline elapsed") }
  if mode == "past" { require(elapsed < 100, "past elapsed") }
  output("RESULT {\"ok\":true,\"mode\":\"" + mode + "\",\"status\":\"" + status.to_string() + "\",\"about\":" + app.about_count.to_string() + ",\"proxy\":" + app.proxy_count.to_string() + ",\"elapsed\":" + elapsed.to_string() + ",\"tid\":" + get_current_thread_id().to_string() + "}")
}

///|
fn run_receiver() -> Unit {
  let event_loop = @windows.EventLoop::new()
  let app = Probe::new("receiver")
  let proxy = event_loop.create_proxy()
  app.proxy = Some(proxy)
  startup_drain(event_loop, app)
  output("READY " + get_current_thread_id().to_string())
  let start = get_tick_count64()
  event_loop.set_control_flow(@core.ControlFlow::Wait)
  let status = event_loop.pump_app_events(Some(1500), app)
  let end = get_tick_count64()
  require(status == @core.PumpStatus::Continue, "receiver pump must continue")
  require(app.proxy_count == 1, "receiver proxy wake count")
  require(end >= start, "receiver clock")
  output("RESULT {\"ok\":true,\"mode\":\"receiver\",\"status\":\"" + status.to_string() + "\",\"proxy\":1,\"start_ms\":" + start.to_string() + ",\"end_ms\":" + end.to_string() + "}")
}

///|
fn require(value : Bool, message : String) -> Unit {
  if !value { abort(message) }
}

///|
fn main {
  let args = @env.args()
  guard args.length() >= 2 else { abort("usage: window_pump_contract MODE [TID]") }
  let mode = args[1]
  guard mode == "poll" || mode == "proxy" || mode == "flood" || mode == "wait" ||
    mode == "deadline" || mode == "past" || mode == "quit" || mode == "receiver" ||
    mode == "sender" else { abort("unknown mode") }
  if mode == "sender" {
    guard args.length() == 3 else { abort("sender requires tid") }
    let tid = @string.parse_uint(args[2]) catch { _ => abort("invalid tid") }
    require(tid > 0U, "tid must be positive")
    let posted_ms = get_tick_count64()
    let posted = post_thread_message(tid, 0x8100, 0, 0L)
    require(posted != 0, "PostThreadMessageW failed")
    output("RESULT {\"ok\":true,\"mode\":\"sender\",\"tid\":" + tid.to_string() + ",\"posted_ms\":" + posted_ms.to_string() + "}")
  } else if mode == "receiver" {
    guard args.length() == 2 else { abort("receiver takes no arguments") }
    run_receiver()
  } else {
    guard args.length() == 2 else { abort("unexpected arguments") }
    run(mode)
  }
}
