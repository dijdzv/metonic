///|
struct Probe {
  mut new_events_count : Int
  mut can_create_surfaces_count : Int
  mut about_to_wait_count : Int
  mut proxy_wake_up_count : Int
  mode : String
}

///|
fn Probe::new(mode : String) -> Probe {
  {
    new_events_count: 0,
    can_create_surfaces_count: 0,
    about_to_wait_count: 0,
    proxy_wake_up_count: 0,
    mode,
  }
}

///|
pub impl @windows.ApplicationHandler for Probe with fn new_events(
  self,
  _event_loop,
  _cause,
) {
  self.new_events_count += 1
}

///|
pub impl @windows.ApplicationHandler for Probe with fn can_create_surfaces(
  self,
  _event_loop,
) {
  self.can_create_surfaces_count += 1
}

///|
pub impl @windows.ApplicationHandler for Probe with fn proxy_wake_up(
  self,
  _event_loop,
) {
  self.proxy_wake_up_count += 1
}

///|
pub impl @windows.ApplicationHandler for Probe with fn about_to_wait(
  self,
  event_loop,
) {
  self.about_to_wait_count += 1
  if self.mode == "poll" && self.about_to_wait_count >= 1000 {
    event_loop.exit()
  }
}

///|
fn print_probe(
  mode : String,
  status : @core.PumpStatus,
  event_loop : @windows.EventLoop,
  app : Probe,
) -> Unit {
  println(
    "PUMP_PROBE mode=" +
    mode +
    " status=" +
    status.to_string() +
    " new_events=" +
    app.new_events_count.to_string() +
    " can_create_surfaces=" +
    app.can_create_surfaces_count.to_string() +
    " about_to_wait=" +
    app.about_to_wait_count.to_string() +
    " proxy_wake_up=" +
    app.proxy_wake_up_count.to_string() +
    " exiting=" +
    event_loop.exiting().to_string(),
  )
}

///|
fn main {
  let args = @env.args()
  let mode = if args.length() > 1 { args[1] } else { "wait" }
  if mode != "wait" && mode != "poll" && mode != "wait-until" && mode != "proxy" {
    abort("mode must be wait, poll, wait-until, or proxy")
  }
  let event_loop = @windows.EventLoop::new()
  let app = Probe::new(mode)
  if mode == "poll" {
    event_loop.set_control_flow(@core.ControlFlow::Poll)
  } else if mode == "wait-until" {
    // A fixed value avoids adding a native clock bridge; this checks the pump timeout only.
    event_loop.set_control_flow(@core.ControlFlow::wait_until(25L))
  }
  if mode == "proxy" {
    let proxy = event_loop.create_proxy()
    proxy.wake_up()
  }
  println("PUMP_PROBE before mode=" + mode)
  let status = event_loop.pump_app_events(Some(25), app)
  print_probe(mode, status, event_loop, app)
}
