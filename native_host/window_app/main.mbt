///|
extern "C" fn post_message(
  hwnd : UInt64,
  message : UInt,
  wparam : UInt64,
  lparam : Int64,
) -> Int = "PostMessageW"

///|
extern "C" fn is_window(hwnd : UInt64) -> Int = "IsWindow"

///|
suberror WindowFailure {
  Failure(String)
} derive(Debug)

///|
fn require(ok : Bool, message : String) -> Unit raise WindowFailure {
  if !ok {
    raise Failure(message)
  }
}

///|
enum Event {
  Redraw
  Resize(@dpi.PhysicalSize)
  Input(@scene.Action)
  Close
}

///|
struct App {
  event_loop : @windows.EventLoop
  events : @aqueue.Queue[Event]
  state : @scene.State
  is_test : Bool
  mut window : @windows.Window?
  mut error : Error?
  mut hwnd : UInt64
  mut message_hwnd : UInt64
  mut instance : @wgpu.Instance?
  mut surface : @wgpu.Surface?
  owner : @gpu.Initialization
  mut renderer : @gpu.SurfaceRenderer?
  mut frames : Int
  mut closed : Bool
  mut success : String
}

///|
fn App::queue(self : App, event : Event) -> Unit {
  if self.closed {
    return
  }
  require(self.events.try_put(event), "window event queue overflow") catch {
    error => if self.error is None { self.error = Some(error) }
  }
}

///|
pub impl @windows.ApplicationHandler for App with fn can_create_surfaces(
  self,
  event_loop,
) {
  let window = event_loop.create_window(
    @core.WindowAttributes::default()
    .with_visible(!self.is_test)
    .with_inner_size(@dpi.PhysicalSize(640, 360).into_size()),
  )
  self.window = Some(window)
  self.hwnd = window.native_window_handle()
}

///|
pub impl @windows.ApplicationHandler for App with fn proxy_wake_up(
  _self,
  _event_loop,
) {
  ()
}

///|
pub impl @windows.ApplicationHandler for App with fn about_to_wait(
  _self,
  _event_loop,
) {
  ()
}

///|
pub impl @windows.ApplicationHandler for App with fn window_event(
  self,
  _event_loop,
  _id,
  event,
) {
  match event {
    @core.WindowEvent::RedrawRequested => self.queue(Redraw)
    @core.WindowEvent::SurfaceResized(size) => self.queue(Resize(size))
    @core.WindowEvent::CloseRequested => self.queue(Close)
    @core.WindowEvent::KeyboardInput(_, key, false) =>
      if key.state() is @core.ElementState::Pressed {
        match key.logical_key() {
          @core.Key::Named(@core.NamedKey::ArrowLeft) =>
            self.queue(Input(Move(-10, 0)))
          @core.Key::Named(@core.NamedKey::ArrowRight) =>
            self.queue(Input(Move(10, 0)))
          @core.Key::Named(@core.NamedKey::ArrowUp) =>
            self.queue(Input(Move(0, -10)))
          @core.Key::Named(@core.NamedKey::ArrowDown) =>
            self.queue(Input(Move(0, 10)))
          @core.Key::Named(@core.NamedKey::Enter) => self.queue(Input(Activate))
          @core.Key::Character(" ") => self.queue(Input(Activate))
          _ => ()
        }
      }
    @core.WindowEvent::PointerButton(
      _,
      @core.ElementState::Pressed,
      position,
      _,
      @core.ButtonSource::Mouse(@core.MouseButton::Left)
    ) => self.queue(Input(Click(position.x().to_int(), position.y().to_int())))
    _ => ()
  }
}

///|
fn App::draw(self : App) -> Unit raise Error {
  match self.renderer {
    Some(renderer) => {
      renderer.present(
        @scene.field(self.state, 6),
        @scene.field(self.state, 7),
        @scene.field(self.state, 0),
        @scene.field(self.state, 1),
        @scene.field(self.state, 2),
        @scene.field(self.state, 3),
        @scene.field(self.state, 4),
      )
      self.frames += 1
    }
    None => ()
  }
}

///|
fn App::pump(self : App, driver : @loop.Driver) -> Unit raise Error {
  @external.ExternalEventLoop::poll(driver, timeout=0)
  match self.error {
    Some(error) => raise error
    None => ()
  }
}

///|
fn App::post(
  self : App,
  message : UInt,
  wparam : UInt64,
  lparam : Int64,
) -> Unit raise Error {
  require(self.is_test, "test injection requires hidden mode")
  require(
    post_message(self.hwnd, message, wparam, lparam) != 0,
    "PostMessage failed",
  )
}

///|
fn App::finish(self : App) -> Unit raise Error {
  require(
    self.owner.pending_count() == 0,
    "GPU initialization still owns window",
  )
  match self.renderer {
    Some(renderer) => renderer.close()
    None => ()
  }
  self.renderer = None
  match self.surface {
    Some(surface) => surface.release()
    None => ()
  }
  self.surface = None
  match self.instance {
    Some(instance) => instance.release()
    None => ()
  }
  self.instance = None
  match self.window {
    Some(window) => window.drop()
    None => ()
  }
  self.window = None
  self.event_loop.try_drop()
  require(
    is_window(self.hwnd) == 0 && is_window(self.message_hwnd) == 0,
    "window survived cleanup",
  )
  println("WINDOW_CLEANUP_OK")
  match self.error {
    Some(error) => {
      println("WINDOW_PROBE_FAILED")
      raise error
    }
    None => if self.is_test { println(self.success) }
  }
}

///|
async fn main {
  let event_loop = @windows.EventLoop::new()
  let app : App = {
    event_loop,
    events: @aqueue.Queue::Queue(kind=@aqueue.Blocking(64)),
    state: @scene.create(),
    is_test: @env.get_env_var("METONIC_WINDOW_TEST") == Some("1"),
    window: None,
    error: None,
    hwnd: 0UL,
    message_hwnd: 0UL,
    instance: None,
    surface: None,
    owner: @gpu.Initialization::new(),
    renderer: None,
    frames: 0,
    closed: false,
    success: "WINDOW_PROBE_FAILED",
  }
  let driver = @loop.Driver::new(
    event_loop,
    app as &@windows.ApplicationHandler,
    _ => app.finish(),
  )
  @async.set_external_event_loop(driver)
  event_loop.set_control_flow(@core.ControlFlow::Wait)
  try {
    let mode = @env.get_env_var("METONIC_WINDOW_INIT_TEST").unwrap_or("normal")
    require(
      mode == "normal" || mode == "input" || mode == "close",
      "unknown initialization test",
    )
    require(
      mode == "normal" || app.is_test,
      "initialization test requires hidden mode",
    )
    app.pump(driver)
    app.message_hwnd = driver.message_window_handle()
    let window = app.window.unwrap()
    ignore(window.request_inner_size(@dpi.PhysicalSize(640, 360).into_size()))
    app.pump(driver)
    let instance = @wgpu.Instance::create()
    app.instance = Some(instance)
    let surface = instance.create_surface_windows_hwnd(
      @c.opaque_ptr_from_u64(window.rwh_06_display_handle()),
      @c.opaque_ptr_from_u64(app.hwnd),
    )
    app.surface = Some(surface)
    @async.with_task_group() <| group => {
      let init = group.spawn() <| () => {
        app.renderer = Some(
          @gpu.SurfaceRenderer::new(
            instance,
            surface,
            @env.get_env_var("METONIC_GPU_FALLBACK") == Some("1"),
            app.owner,
          ),
        )
      }
      let mut initializing = true
      let mut retained = false
      let mut polls = 0
      let mut stage = 0
      if mode != "normal" {
        @async.pause()
        require(
          app.owner.pending_count() > 0,
          "initialization ticket not retained",
        )
        app.post(if mode == "input" { 0x0100U } else { 0x0010U }, 0x27UL, 0L)
      }
      while !app.closed {
        app.pump(driver)
        while app.events.try_get() is Some(event) {
          match event {
            Close => app.closed = true
            Resize(size) =>
              if size.width() > 0 && size.height() > 0 {
                if @scene.resize(app.state, size.width(), size.height()) {
                  app.draw()
                }
              }
            Redraw => app.draw()
            Input(action) =>
              if @scene.dispatch(app.state, action) {
                app.draw()
              }
          }
          if initializing && mode != "normal" && !retained {
            let observed = match event {
              Close => mode == "close"
              Input(Move(10, 0)) => mode == "input"
              _ => false
            }
            if observed {
              require(
                app.owner.pending_count() > 0,
                "host event arrived after initialization ownership released",
              )
              retained = true
              println(
                "WINDOW_INIT_RETAINED=" + app.owner.pending_count().to_string(),
              )
            }
          }
        }
        if app.closed {
          break
        }
        if initializing && (mode == "normal" || retained) {
          if init.try_wait() is Some(_) {
            init.wait()
            initializing = false
            if mode == "input" {
              require(
                @scene.field(app.state, 0) == 270,
                "first frame lost initialization input",
              )
            }
            app.draw()
            if app.is_test && mode == "normal" {
              app.post(0x0100U, 0x27UL, 0L)
            }
          }
        }
        if app.is_test && !initializing {
          if stage == 0 && @scene.field(app.state, 0) == 270 {
            stage = 1
            ignore(
              window.request_inner_size(@dpi.PhysicalSize(317, 193).into_size()),
            )
          } else if stage == 1 &&
            @scene.field(app.state, 6) == 317 &&
            @scene.field(app.state, 7) == 193 {
            stage = 2
            let packed = ((@scene.field(app.state, 1) + 1) << 16) |
              (@scene.field(app.state, 0) + 1)
            app.post(0x0201U, 1UL, packed.to_int64())
          } else if stage == 2 && @scene.field(app.state, 4) == 1 {
            stage = 3
            app.post(0x0010U, 0UL, 0L)
          }
        }
        if initializing && mode != "normal" && !retained {
          polls += 1
          require(polls <= 64, "initialization host event poll limit exceeded")
        } else {
          @async.sleep(1)
        }
      }
      if initializing {
        init.cancel()
        init.wait() catch {
          error if @async.is_cancellation_error(error) => ()
          error => raise error
        }
      }
      if mode != "normal" {
        require(retained, "initialization event not observed")
        println(
          "WINDOW_INIT_REMAINING=" + app.owner.pending_count().to_string(),
        )
      }
      if app.is_test {
        if mode == "close" {
          require(
            app.frames == 0 &&
            app.renderer is None &&
            app.owner.pending_count() == 0,
            "initialization close failed",
          )
          app.success = "WINDOW_INIT_CLOSE_OK"
        } else {
          require(
            stage == 3 &&
            app.frames >= 3 &&
            @scene.field(app.state, 4) == 1 &&
            @scene.field(app.state, 6) == 317 &&
            @scene.field(app.state, 7) == 193,
            "window scenario failed",
          )
          app.success = if mode == "input" {
            "WINDOW_INIT_INPUT_OK"
          } else {
            "WINDOW_PROBE_OK"
          }
        }
      }
    }
  } catch {
    error => app.error = Some(error)
  }
}
