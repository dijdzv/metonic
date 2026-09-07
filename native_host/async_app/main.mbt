///|
extern "C" fn post_message(hwnd : UInt64, message : UInt, wparam : UInt64, lparam : Int64) -> Int = "PostMessageW"

///|
extern "C" fn is_window(hwnd : UInt64) -> Int = "IsWindow"

///|
const WM_KEYDOWN : UInt = 0x0100

///|
const WM_CLOSE : UInt = 0x0010

///|
const VK_RIGHT : UInt64 = 0x27

///|
enum AppEvent {
  Redraw
  Resize(@dpi.PhysicalSize)
  RightKey
  Close
}

///|
enum JobResult {
  Complete(Int, Int)
  Failed(Int, Int)
}

///|
suberror AsyncFailure {
  Failure(String)
} derive(Debug)

///|
struct App {
  event_loop : @windows.EventLoop
  events : @aqueue.Queue[AppEvent]
  results : @aqueue.Queue[JobResult]
  mut callback_error : Error?
  mut closing : Bool
  mut close_received : Bool
  mut responsive : Bool
  scene : @scene.State
  scope : @task_scope.Scope
  mut rejected : Int
  mut admission_rejected : Int
  mut stage : Int
  mut pending : Int
  mut active : Int
  slots : Map[Int, @async.Task[Unit]?]
  mut saved_results : Array[JobResult]
  mut window : @windows.Window?
  mut app_hwnd : UInt64
  mut message_hwnd : UInt64
  mut instance : @wgpu.Instance?
  mut surface : @wgpu.Surface?
  mut initialization : @gpu.Initialization?
  mut renderer : @gpu.SurfaceRenderer?
  mut frames : Int
  mut adapter : String
  mut main_done : Bool
  mut original_error : Error?
  mut original_error_text : String
  mut io_wakes : Int
  mut io_proxies : Int
  mut io_indefinite : Int
  mut proxy_count : Int
  mut before_wakes : Int
  mut before_proxies : Int
  mut before_indefinite : Int
  mut shutdown_ms : Int64
}

///|
fn App::new(event_loop : @windows.EventLoop) -> App {
  {
    event_loop,
    events: @aqueue.Queue::Queue(kind=@aqueue.Blocking(64)),
    results: @aqueue.Queue::Queue(kind=@aqueue.Blocking(64)),
    callback_error: None,
    closing: false,
    close_received: false,
    responsive: false,
    scene: @scene.create(),
    scope: @task_scope.create(),
    rejected: 0,
    admission_rejected: 0,
    stage: 0,
    pending: 0,
    active: 0,
    slots: Map([]),
    saved_results: [],
    window: None,
    app_hwnd: 0UL,
    message_hwnd: 0UL,
    instance: None,
    surface: None,
    initialization: None,
    renderer: None,
    frames: 0,
    adapter: "",
    main_done: false,
    original_error: None,
    original_error_text: "",
    io_wakes: 0,
    io_proxies: 0,
    io_indefinite: 0,
    proxy_count: 0,
    before_wakes: 0,
    before_proxies: 0,
    before_indefinite: 0,
    shutdown_ms: 0L,
  }
}

///|
fn App::record_callback_error(self : App, error : Error) -> Unit {
  if self.callback_error is None {
    self.callback_error = Some(error)
  }
}

///|
fn App::queue_event(self : App, event : AppEvent) -> Unit {
  if self.closing {
    return
  }
  try {
    if !self.events.try_put(event) {
      self.record_callback_error(AsyncFailure::Failure("window event queue overflow"))
    }
  } catch {
    error => self.record_callback_error(error)
  }
}

///|
pub impl @windows.ApplicationHandler for App with fn can_create_surfaces(
  self,
  event_loop,
) {
  let attrs = @core.WindowAttributes::default()
    .with_visible(false)
    .with_inner_size(@dpi.PhysicalSize(640, 360).into_size())
  let window = event_loop.create_window(attrs)
  self.app_hwnd = window.native_window_handle()
  self.window = Some(window)
  let instance : @wgpu.Instance? = Some(@wgpu.Instance::create()) catch {
    error => {
      self.record_callback_error(error)
      None
    }
  }
  match instance {
    None => ()
    Some(instance) => {
      let surface = instance.create_surface_windows_hwnd(
        @c.opaque_ptr_from_u64(self.window.unwrap().rwh_06_display_handle()),
        @c.opaque_ptr_from_u64(self.app_hwnd),
      )
      self.instance = Some(instance)
      self.surface = Some(surface)
      self.initialization = Some(@gpu.Initialization::new())
    }
  }
}

///|
pub impl @windows.ApplicationHandler for App with fn proxy_wake_up(
  self,
  _event_loop,
) {
  self.proxy_count += 1
}

///|
pub impl @windows.ApplicationHandler for App with fn window_event(
  self,
  _event_loop,
  _id,
  event,
) {
  match event {
    @core.WindowEvent::RedrawRequested => self.queue_event(Redraw)
    @core.WindowEvent::SurfaceResized(size) => self.queue_event(Resize(size))
    @core.WindowEvent::CloseRequested => {
      if !self.closing {
        self.queue_event(Close)
      }
    }
    @core.WindowEvent::KeyboardInput(_, key, false) => {
      if !self.closing &&
        key.state() is @core.ElementState::Pressed &&
        key.logical_key() is @core.Key::Named(@core.NamedKey::ArrowRight) {
        self.queue_event(RightKey)
      }
    }
    _ => ()
  }
}

///|
pub impl @windows.ApplicationHandler for App with fn about_to_wait(
  _self,
  _event_loop,
) {
  ()
}

///|
fn require(value : Bool, message : String) -> Unit raise AsyncFailure {
  if !value {
    raise AsyncFailure::Failure(message)
  }
}

///|
fn App::check_callback_error(self : App) -> Unit raise Error {
  match self.callback_error {
    Some(error) => raise error
    None => ()
  }
}

///|
fn App::draw(self : App) -> Unit raise Error {
  match self.renderer {
    Some(renderer) => {
      renderer.present(
        @scene.field(self.scene, 6),
        @scene.field(self.scene, 7),
        @scene.field(self.scene, 0),
        @scene.field(self.scene, 1),
        @scene.field(self.scene, 2),
        @scene.field(self.scene, 3),
        @scene.field(self.scene, 4),
      )
      self.frames += 1
    }
    None => raise AsyncFailure::Failure("redraw before renderer")
  }
}

///|
fn App::drain_events(self : App) -> Unit raise Error {
  while self.events.try_get() is Some(event) {
    match event {
      Redraw => self.draw()
      Resize(size) => {
        ignore(@scene.resize(self.scene, size.width(), size.height()))
      }
      RightKey => {
        self.responsive = true
        ignore(@scene.move_to(self.scene, 270, @scene.field(self.scene, 1)))
      }
      Close => {
        self.closing = true
        self.close_received = true
      }
    }
  }
  self.check_callback_error()
}

///|
fn App::pump(self : App, driver : @loop.Driver, timeout : Int?) -> Unit raise Error {
  match timeout {
    Some(timeout) => @external.ExternalEventLoop::poll(driver, timeout=timeout)
    None => @external.ExternalEventLoop::poll(driver)
  }
  self.drain_events()
}

///|
async fn App::wait_until(self : App, driver : @loop.Driver, condition : () -> Bool) -> Unit raise Error {
  let deadline = @async.now() + 5000L
  while !condition() {
    require(@async.now() < deadline, "async scenario timed out")
    self.pump(driver, Some(10))
    @async.pause()
  }
}

///|
async fn App::job(self : App, id : Int, delay : Int, value : Int, fail : Bool) -> Unit {
  self.active += 1
  defer { self.active -= 1 }
  let path = match @env.get_env_var("METONIC_ASYNC_INPUT") {
    Some(path) => path
    None => "experiments/window_async_contract/input.txt"
  }
  let content = @fs.read_file(path).text()
  if content != "metonic async wake\n" {
    raise AsyncFailure::Failure("unexpected input sentinel")
  }
  @async.sleep(delay)
  if fail {
    if !self.results.try_put(Failed(id, 7)) {
      raise AsyncFailure::Failure("job result queue overflow")
    }
  } else if !self.results.try_put(Complete(id, value)) {
    raise AsyncFailure::Failure("job result queue overflow")
  }
}

///|
fn App::start_job(
  self : App,
  group : @async.TaskGroup[Unit],
  id : Int,
  delay : Int,
  value : Int,
  fail : Bool,
) -> Bool {
  if id <= 0 || delay < 1 || delay > 5000 || self.closing || self.slots.length() >= 16 {
    self.admission_rejected += 1
    return false
  }
  if self.slots.get(id) is Some(_) {
    self.admission_rejected += 1
    return false
  }
  self.slots.set(id, None)
  let task = group.spawn(() => self.job(id, delay, value, fail))
  self.slots.set(id, Some(task))
  self.pending += 1
  true
}

///|
async fn App::consume_result(self : App, id : Int) -> JobResult? raise Error {
  while true {
    let mut found : JobResult? = None
    let rest : Array[JobResult] = []
    for result in self.saved_results {
      let result_id = match result {
        Complete(value, _) => value
        Failed(value, _) => value
      }
      if result_id == id { found = Some(result) } else { rest.push(result) }
    }
    self.saved_results = rest
    match found {
      Some(result) => {
        self.slots.remove(id)
        self.pending -= 1
        return Some(result)
      }
      None => {
        let result = self.results.get()
        let result_id = match result {
          Complete(value, _) => value
          Failed(value, _) => value
        }
        if result_id == id {
          self.slots.remove(id)
          self.pending -= 1
          return Some(result)
        }
        self.saved_results.push(result)
      }
    }
  } nobreak { None }
}
///|
fn App::cancel_all(self : App) -> Unit {
  let entries = self.slots.iter()
  while entries.next() is Some((_, slot)) {
    match slot {
      Some(task) => task.cancel()
      _ => ()
    }
  }
}

///|
fn App::finish(self : App, stats : @loop.Snapshot) -> Unit raise Error {
  let mut retained = self.original_error
  let keep = (error : Error) => if retained is None { retained = Some(error) }
  try require(self.pending == 0, "pending jobs remain") catch { error => keep(error) }
  try require(self.active == 0, "active jobs remain") catch { error => keep(error) }
  let init_ready = try {
    match self.initialization {
      Some(init) => { require(init.pending_count() == 0, "GPU initialization pending"); true }
      None => true
    }
  } catch {
    error => { keep(error); false }
  }
  let resources_ready = self.pending == 0 && self.active == 0 && init_ready
  if resources_ready {
    match self.renderer { Some(renderer) => renderer.close(); None => () }
    match self.surface { Some(surface) => surface.release(); None => () }
    match self.instance { Some(instance) => instance.release(); None => () }
    match self.window {
      Some(window) => { window.drop(); self.window = None }
      None => ()
    }
  }
  let hwnd_destroyed : Bool = is_window(self.app_hwnd) == 0
  if resources_ready { try self.event_loop.try_drop() catch { error => keep(error) } }
  let message_destroyed : Bool = is_window(self.message_hwnd) == 0
  if resources_ready {
    try require(hwnd_destroyed, "hidden window survived drop") catch { error => keep(error) }
    try require(message_destroyed, "message window survived drop") catch { error => keep(error) }
  }
  let ok : Bool = retained is None && self.main_done && self.close_received &&
    self.rejected == 3 && self.stage == 6 && @scene.field(self.scene, 0) == 90 &&
    @task_scope.field(self.scope, 0) == 5 && self.pending == 0 && self.active == 0 &&
    hwnd_destroyed && message_destroyed && stats.wakes > 0 &&
    stats.finite_count > 0 && stats.indefinite_count > 0 && self.proxy_count > 0 &&
    self.frames >= 4 && self.io_wakes > 0 && self.io_proxies > 0 && self.io_indefinite > 0 &&
    self.admission_rejected == 2
  if !ok && retained is None {
    retained = Some(AsyncFailure::Failure("native async scenario invariants failed"))
  }
  let error_json : String = match retained {
    Some(error) => {
      if self.original_error_text == "" { self.original_error_text = @debug.to_string(error) }
      Json::string(self.original_error_text).stringify()
    }
    None => "null"
  }
  let line = "NATIVE_ASYNC_RESULT {\"ok\":" + ok.to_string() +
    ",\"original_error\":" + error_json +
    ",\"responsive\":" + self.responsive.to_string() +
    ",\"rejected\":" + self.rejected.to_string() +
    ",\"stage\":" + self.stage.to_string() +
    ",\"scene_x\":" + @scene.field(self.scene, 0).to_string() +
    ",\"status\":" + @task_scope.field(self.scope, 0).to_string() +
    ",\"pending\":" + self.pending.to_string() +
    ",\"active\":" + self.active.to_string() +
    ",\"closed\":" + self.closing.to_string() +
    ",\"adapter\":" + Json::string(self.adapter).stringify() +
    ",\"frames\":" + self.frames.to_string() +
    ",\"io_wakes\":" + self.io_wakes.to_string() +
    ",\"io_proxies\":" + self.io_proxies.to_string() +
    ",\"io_indefinite\":" + self.io_indefinite.to_string() +
    ",\"hwnd_destroyed\":" + hwnd_destroyed.to_string() +
    ",\"message_hwnd_destroyed\":" + message_destroyed.to_string() + "}"
  println("NATIVE_ASYNC_SHUTDOWN_MS=" + self.shutdown_ms.to_string())
  println(line)
  match retained {
    Some(error) => { println("NATIVE_ASYNC_FAILED"); raise error }
    None => println("NATIVE_ASYNC_OK")
  }
}
///|
async fn main {
  guard @env.get_env_var("METONIC_WINDOW_TEST") == Some("1") else {
    abort("METONIC_WINDOW_TEST=1 is required")
  }
  let event_loop = @windows.EventLoop::new()
  let app = App::new(event_loop)
  let driver = @loop.Driver::new(event_loop, app as &@windows.ApplicationHandler, stats => app.finish(stats))
  @async.set_external_event_loop(driver)
  event_loop.set_control_flow(@core.ControlFlow::Wait)
  try {
    app.pump(driver, Some(0))
    app.message_hwnd = driver.message_window_handle()
    require(is_window(app.message_hwnd) != 0, "message window was not created")
    match app.window {
      Some(window) => {
        ignore(window.request_inner_size(@dpi.PhysicalSize(640, 360).into_size()))
        app.wait_until(driver, () => match app.window {
          Some(window) => {
            let size = window.inner_size()
            size.width() == 640 && size.height() == 360
          }
          None => false
        })
      }
      None => raise AsyncFailure::Failure("hidden window was not created")
    }
    match app.window {
      Some(window) => {
        let size = window.inner_size()
        require(size.width() == 640 && size.height() == 360, "unexpected client size")
      }
      None => raise AsyncFailure::Failure("hidden window disappeared")
    }
    match (app.instance, app.surface, app.initialization) {
      (Some(instance), Some(surface), Some(init)) => {
        let renderer = @gpu.SurfaceRenderer::new(instance, surface, @env.get_env_var("METONIC_GPU_FALLBACK") == Some("1"), init)
        app.renderer = Some(renderer)
        app.adapter = renderer.adapter_name()
        app.draw()
        app.before_wakes = driver.snapshot().wakes
        app.before_proxies = app.proxy_count
        app.before_indefinite = driver.snapshot().indefinite_count
      }
      _ => raise AsyncFailure::Failure("GPU resources were not initialized")
    }
    @async.with_task_group <| group => {
      group.add_defer(() => {
        @async.protect_from_cancel <| () => {
          app.slots.clear()
          app.pending = 0
          app.events.close(clear=true)
          app.results.close(clear=true)
        }
      })
      let first = @task_scope.begin(app.scope)
      require(first > 0, "scope begin1 failed")
      require(app.start_job(group, first, 200, 40, false), "job1 start failed")
      require(post_message(app.app_hwnd, WM_KEYDOWN, VK_RIGHT, 0L) != 0, "right key post failed")
      app.wait_until(driver, () => app.responsive)
      require(@task_scope.field(app.scope, 0) == 1 && @scene.field(app.scene, 0) == 270, "job1 responsiveness failed")
      app.draw()
      match app.consume_result(first) {
        Some(Complete(_, value)) => { require(@task_scope.complete(app.scope, first, value), "completion1 rejected"); ignore(@scene.move_to(app.scene, 40, @scene.field(app.scene, 1))); app.draw() }
        _ => raise AsyncFailure::Failure("completion1 failed")
      }
      app.stage = 1
      let old = @task_scope.begin(app.scope)
      let fresh = @task_scope.begin(app.scope)
      require(old > 0 && fresh > 0, "scope begin2 failed")
      require(app.start_job(group, old, 300, 50, false), "old job start failed")
      require(app.start_job(group, fresh, 20, 90, false), "fresh job start failed")
      match app.consume_result(fresh) { Some(Complete(_, value)) => { require(@task_scope.complete(app.scope, fresh, value), "completion3 rejected"); ignore(@scene.move_to(app.scene, value, @scene.field(app.scene, 1))); app.draw() }; _ => raise AsyncFailure::Failure("completion3 failed") }
      match app.consume_result(old) {
        Some(Complete(_, value)) => {
          require(!@task_scope.complete(app.scope, old, value), "old completion accepted")
          app.rejected += 1
        }
        _ => raise AsyncFailure::Failure("completion2 failed")
      }
      app.stage = 2
      let four = @task_scope.begin(app.scope)
      require(app.start_job(group, four, 20, 110, false), "job4 start failed")
      require(@task_scope.cancel(app.scope), "scope cancel failed")
      match app.consume_result(four) {
        Some(Complete(_, value)) => {
          require(!@task_scope.complete(app.scope, four, value), "late completion4 accepted")
          app.rejected += 1
        }
        _ => raise AsyncFailure::Failure("late completion4 missing")
      }
      require(@task_scope.field(app.scope, 0) == 4 && @scene.field(app.scene, 0) == 90, "cancel4 state mismatch")
      app.stage = 3
      let five = @task_scope.begin(app.scope)
      require(app.start_job(group, five, 20, 0, true), "job5 start failed")
      match app.consume_result(five) { Some(Failed(_, code)) => require(@task_scope.fail(app.scope, five, code), "failure5 rejected"); _ => raise AsyncFailure::Failure("failure5 missing") }
      app.stage = 4
      require(@task_scope.field(app.scope, 0) == 3 && @task_scope.field(app.scope, 3) == 7 && @scene.field(app.scene, 0) == 90, "failure5 state mismatch")
      let six = @task_scope.begin(app.scope)
      require(app.start_job(group, six, 20, 120, false), "job6 start failed")
      require(@task_scope.dispose(app.scope), "scope dispose failed")
      match app.consume_result(six) {
        Some(Complete(_, value)) => {
          require(!@task_scope.complete(app.scope, six, value), "late completion6 accepted")
          app.rejected += 1
        }
        _ => raise AsyncFailure::Failure("late completion6 missing")
      }
      require(@task_scope.field(app.scope, 0) == 5 && @scene.field(app.scene, 0) == 90, "dispose6 state mismatch")
      app.stage = 5
      let io_snap = driver.snapshot()
      app.io_wakes = io_snap.wakes - app.before_wakes
      app.io_proxies = app.proxy_count - app.before_proxies
      app.io_indefinite = io_snap.indefinite_count - app.before_indefinite
      require(app.io_wakes > 0 && app.io_proxies > 0 && app.io_indefinite > 0, "async IO wake/proxy missing")
      for id in 1000..<1016 { require(app.start_job(group, id, 5000, 0, false), "long job admission failed") }
      app.wait_until(driver, () => app.active == 16)
      require(!app.start_job(group, 1016, 5000, 0, false), "17th job admitted")
      require(app.pending == 16, "pending16 missing")
      require(post_message(app.app_hwnd, WM_CLOSE, 0UL, 0L) != 0, "close post failed")
      app.wait_until(driver, () => app.close_received)
      app.stage = 6
      app.closing = true
      let shutdown_start = @async.now()
      app.cancel_all()
      let mut join_error : Error? = None
      for id in 1000..<1016 {
        match app.slots.get(id) {
          Some(Some(task)) =>
            try task.wait() catch {
              error if @async.is_cancellation_error(error) => ()
              error => if join_error is None { join_error = Some(error) }
            }
          _ => ()
        }
      }
      app.shutdown_ms = @async.now() - shutdown_start
      match join_error { Some(error) => raise error; None => () }
      app.slots.clear()
      app.pending = 0
    }
    @async.with_task_group <| group => {
      require(!app.start_job(group, 2000, 1, 0, false), "start after shutdown admitted")
    }
  } catch {
    error => {
      app.closing = true
      app.original_error = Some(error)
      app.original_error_text = @debug.to_string(error)
    }
  }
  app.main_done = true
}
