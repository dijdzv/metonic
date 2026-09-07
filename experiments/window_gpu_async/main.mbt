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
extern "C" fn message_window() -> UInt64 = "metonic_async_message_window"

///|
struct Probe {
  event_loop : @windows.EventLoop
  mut zero_count : Int
  mut finite_count : Int
  mut indefinite_count : Int
  mut proxy_count : Int
  mut main_done : Bool
  mut original_error : Error?
  mut original_error_text : String
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
  mut message_hwnd : UInt64
  mut instance : @wgpu.Instance?
  mut surface : @wgpu.Surface?
  mut initialization : @gpu.Initialization?
  mut renderer : @gpu.SurfaceRenderer?
  mut frames : Int
  mut redraws : Int
  mut resizes : Int
  mut width : Int
  mut height : Int
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
    original_error: None,
    original_error_text: "",
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
    message_hwnd: 0UL,
    instance: None,
    surface: None,
    initialization: None,
    renderer: None,
    frames: 0,
    redraws: 0,
    resizes: 0,
    width: 640,
    height: 360,
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
  let instance : @wgpu.Instance? = Some(@wgpu.Instance::create()) catch {
    error => {
      self.original_error = Some(error)
      self.original_error_text = "GPU initialization failed"
      None
    }
  }
  match instance {
    None => return
    Some(instance) => {
      let surface = instance.create_surface_windows_hwnd(
        @c.opaque_ptr_from_u64(window.rwh_06_display_handle()),
        @c.opaque_ptr_from_u64(self.hwnd),
      )
      self.instance = Some(instance)
      self.surface = Some(surface)
      self.initialization = Some(@gpu.Initialization::new())
    }
  }
}

///|
pub impl @windows.ApplicationHandler for Probe with fn proxy_wake_up(
  self,
  _event_loop,
) {
  self.proxy_count += 1
}

///|
pub impl @windows.ApplicationHandler for Probe with fn window_event(
  self,
  _event_loop,
  _id,
  event,
) {
  match event {
    @core.WindowEvent::RedrawRequested => {
      self.redraws += 1
      match self.renderer {
        Some(renderer) => {
          renderer.present(
            self.width,
            self.height,
            0,
            0,
            self.width,
            self.height,
            0,
          ) catch {
            error => {
              self.original_error = Some(error)
              self.original_error_text = @debug.to_string(error)
            }
          }
          if self.original_error is None {
            self.frames += 1
          }
        }
        None => ()
      }
    }
    @core.WindowEvent::SurfaceResized(size) => {
      self.width = size.width
      self.height = size.height
      self.resizes += 1
    }
    _ => ()
  }
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
  require(self.pending == 0, "pending tasks remain")
  match self.initialization {
    Some(initialization) =>
      require(initialization.pending_count() == 0, "GPU initialization pending")
    None => ()
  }
  let no_error = self.original_error is None
  if no_error {
    require(wake_count() > 0, "no foreign wake")
    require(failed_wake_count() == 0, "foreign wake failed")
    require(self.proxy_count > 0, "no proxy callback")
    require(self.finite_count > 0, "no finite poll")
    require(self.zero_count > 0, "no zero poll")
    require(self.indefinite_count > 0, "no indefinite poll")
  }
  match self.renderer {
    Some(renderer) => renderer.close()
    None => ()
  }
  match self.surface {
    Some(surface) => surface.release()
    None => ()
  }
  match self.instance {
    Some(instance) => instance.release()
    None => ()
  }
  match self.window {
    Some(window) => {
      window.drop()
      self.window = None
      require(is_window(self.hwnd) == 0, "hidden window survived drop")
    }
    None => abort("missing hidden window")
  }
  self.event_loop.try_drop()
  require(is_window(self.message_hwnd) == 0, "message window survived drop")
  self.event_loop.try_drop()
  let closed_pump = self.event_loop.try_pump_app_events(Some(0), self)
  match closed_pump {
    @core.PumpStatus::Exit(code) => require(code == 0, "closed pump exit code")
    @core.PumpStatus::Continue => abort("closed pump continued")
  }
  let closed_create_error : Error? = try {
    let window = self.event_loop.try_create_window(
      @core.WindowAttributes::default().with_visible(false),
    )
    window.drop()
    None
  } catch {
    error => Some(error)
  }
  require(closed_create_error is Some(_), "closed create window did not fail")
  let error_json = match self.original_error {
    Some(_) => Json::string(self.original_error_text).stringify()
    None => "null"
  }
  let line = "RESULT {\"ok\":" +
    (self.main_done && no_error).to_string() +
    ",\"mode\":\"gpu_async\",\"pending\":" +
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
    ",\"hwnd_destroyed\":true,\"message_hwnd_destroyed\":true,\"adapter\":" +
    (match self.renderer {
      Some(renderer) => Json::string(renderer.adapter_name()).stringify()
      None => "null"
    }) +
    ",\"frames\":" +
    self.frames.to_string() +
    ",\"redraws\":" +
    self.redraws.to_string() +
    ",\"resizes\":" +
    self.resizes.to_string() +
    ",\"width\":" +
    self.width.to_string() +
    ",\"height\":" +
    self.height.to_string() +
    ",\"initialization_pending\":" +
    (match self.initialization {
      Some(init) => init.pending_count().to_string()
      None => "0"
    }) +
    ",\"original_error\":" +
    error_json +
    "}"
  println(line)
  match self.original_error {
    Some(error) => raise error
    None => ()
  }
}

///|
suberror ProbeFailure {
  Failure(String)
} derive(Debug)

///|
fn require(value : Bool, message : String) -> Unit raise ProbeFailure {
  if !value {
    raise ProbeFailure::Failure(message)
  }
}

///|
async fn main {
  let args = @env.args()
  guard args.length() == 2 else {
    abort("usage: metonic_gpu_async ABSOLUTE_INPUT")
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
  probe.message_hwnd = message_window()
  require(is_window(probe.message_hwnd) != 0, "message window was not created")
  let app_drop_error : Error? = try {
    probe.event_loop.try_drop()
    None
  } catch {
    error => Some(error)
  }
  require(app_drop_error is Some(_), "drop with app window did not fail")
  require(is_window(probe.hwnd) != 0, "app window lost after failed drop")
  require(
    is_window(probe.message_hwnd) != 0,
    "message window lost after failed drop",
  )
  try {
    match (probe.instance, probe.surface, probe.initialization) {
      (Some(instance), Some(surface), Some(initialization)) => {
        let renderer = @gpu.SurfaceRenderer::new(
          instance,
          surface,
          @env.get_env_var("METONIC_GPU_FALLBACK") == Some("1"),
          initialization,
        )
        probe.renderer = Some(renderer)
        require(
          initialization.pending_count() == 0,
          "GPU initialization pending",
        )
        match probe.renderer {
          Some(renderer) => renderer.present(640, 360, 0, 0, 640, 360, 0)
          None => abort("renderer was not initialized")
        }
        probe.frames = 1
        let start_redraws = probe.redraws
        let start_frames = probe.frames
        match probe.window {
          Some(window) =>
            for _ in 0..<3 {
              window.request_redraw()
            }
          None => abort("hidden window disappeared")
        }
        let redraw_deadline = @async.now() + 2000L
        while probe.redraws == start_redraws && @async.now() < redraw_deadline {
          @external_loop_integration.ExternalEventLoop::poll(probe, timeout=10)
          @async.pause()
        }
        match probe.original_error {
          Some(error) => raise error
          None => ()
        }
        require(
          probe.redraws == start_redraws + 1,
          "no redraw callback frames=" +
          probe.frames.to_string() +
          " redraws=" +
          probe.redraws.to_string() +
          " resizes=" +
          probe.resizes.to_string(),
        )
        require(
          probe.frames == start_frames + 1,
          "redraw did not present frames=" +
          probe.frames.to_string() +
          " redraws=" +
          probe.redraws.to_string() +
          " resizes=" +
          probe.resizes.to_string(),
        )
        let redraws_after = probe.redraws
        let frames_after = probe.frames
        @external_loop_integration.ExternalEventLoop::poll(probe, timeout=0)
        require(
          probe.redraws == redraws_after && probe.frames == frames_after,
          "redraw coalescing failed frames=" +
          probe.frames.to_string() +
          " redraws=" +
          probe.redraws.to_string() +
          " resizes=" +
          probe.resizes.to_string(),
        )
        let start_resizes = probe.resizes
        match probe.window {
          Some(window) =>
            ignore(
              window.request_inner_size(@dpi.PhysicalSize(800, 450).into_size()),
            )
          None => abort("hidden window disappeared")
        }
        let resize_deadline = @async.now() + 2000L
        while probe.resizes == start_resizes && @async.now() < resize_deadline {
          @external_loop_integration.ExternalEventLoop::poll(probe, timeout=10)
          @async.pause()
        }
        require(
          probe.resizes > start_resizes,
          "no resize callback frames=" +
          probe.frames.to_string() +
          " redraws=" +
          probe.redraws.to_string() +
          " resizes=" +
          probe.resizes.to_string(),
        )
        let resize_frames = probe.frames
        match probe.window {
          Some(window) => window.request_redraw()
          None => abort("hidden window disappeared")
        }
        let frame_deadline = @async.now() + 2000L
        while probe.frames == resize_frames && @async.now() < frame_deadline {
          @external_loop_integration.ExternalEventLoop::poll(probe, timeout=10)
          @async.pause()
        }
        match probe.original_error {
          Some(error) => raise error
          None => ()
        }
        require(
          probe.frames > resize_frames,
          "no resize redraw frame frames=" +
          probe.frames.to_string() +
          " redraws=" +
          probe.redraws.to_string() +
          " resizes=" +
          probe.resizes.to_string(),
        )
        require(probe.frames >= 3, "insufficient GPU frames")
        require(
          probe.width == 800 && probe.height == 450,
          "unexpected final size width=" +
          probe.width.to_string() +
          " height=" +
          probe.height.to_string(),
        )
      }
      _ => abort("GPU resources were not initialized")
    }
    let io_wakes_before = wake_count()
    let io_proxies_before = probe.proxy_count
    let io_indefinite_before = probe.indefinite_count
    let content = @fs.read_file(args[1]).text()
    require(content == "metonic async wake\n", "unexpected input sentinel")
    probe.io_wakes = wake_count() - io_wakes_before
    probe.io_proxies = probe.proxy_count - io_proxies_before
    probe.io_indefinite = probe.indefinite_count - io_indefinite_before
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
  } catch {
    error => {
      probe.original_error = Some(error)
      probe.original_error_text = @debug.to_string(error)
    }
  }
  probe.main_done = true
}
