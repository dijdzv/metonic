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
priv enum Event {
  Redraw
  Resize(@dpi.PhysicalSize)
  Input(@scene.Action)
  Commit(String)
  Backspace
  StartUpdate
  CancelUpdate
  Updated(Int, Int)
  Barrier(Ref[Bool])
  Capture(Ref[Result[Captured, Error]?])
  Edit(String?, Int?, Ref[String?])
  Close
}

///|
struct App {
  event_loop : @windows.EventLoop
  events : @aqueue.Queue[Event]
  state : @scene.State
  editor : @semantics.Tree
  scope : @task_scope.Scope
  mut rejected_updates : Int
  mut raster : @raster.Engine?
  mut rendered_text : String?
  mut text_width : Int
  is_test : Bool
  hidden : Bool
  report : (String) -> Unit
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
    .with_visible(!self.is_test && !self.hidden)
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
    @core.WindowEvent::Ime(@core.Ime::Commit(value)) =>
      if value != "\u{0008}" && value != "\r" && value != "\n" && value != "\t" {
        self.queue(Commit(value))
      }
    @core.WindowEvent::KeyboardInput(_, key, false) =>
      if key.state() is @core.ElementState::Pressed {
        match key.logical_key() {
          @core.Key::Named(@core.NamedKey::F5) => self.queue(StartUpdate)
          @core.Key::Named(@core.NamedKey::F6) => self.queue(CancelUpdate)
          @core.Key::Named(@core.NamedKey::Backspace) => self.queue(Backspace)
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
      let text = @semantics.snapshot(self.editor)[1].value
      let width = (@scene.field(self.state, 6) - 16).max(1).min(640)
      if self.rendered_text != Some(text) || self.text_width != width {
        let pixels = @raster.render(self.raster.unwrap(), text, width, 96)
        renderer.set_text_pixels(width, 96, pixels)
        self.rendered_text = Some(text)
        self.text_width = width
      }
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
  (self.report)("WINDOW_CLEANUP_OK")
  match self.error {
    Some(error) => {
      (self.report)("WINDOW_PROBE_FAILED")
      raise error
    }
    None => if self.is_test { (self.report)(self.success) }
  }
}

///|
pub async fn run(
  controller? : (async (Handle) -> Unit)? = None,
  hidden? : Bool = false,
  report? : (String) -> Unit = println,
) -> Unit {
  let event_loop = @windows.EventLoop::new()
  let app : App = {
    event_loop,
    events: @aqueue.Queue::Queue(kind=@aqueue.Blocking(64)),
    state: @scene.create(),
    editor: @semantics.create(1, 1),
    scope: @task_scope.create(),
    rejected_updates: 0,
    raster: None,
    rendered_text: None,
    text_width: 0,
    is_test: @env.get_env_var("METONIC_WINDOW_TEST") == Some("1"),
    hidden,
    report,
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
    app.raster = @raster.create(
      @fs.read_file(
        @env.get_env_var("METONIC_FONT_PATH").unwrap_or(
          ".work/text-assets/NotoSansJP.ttf",
        ),
      ).binary(),
    )
    require(app.raster is Some(_), "font could not be loaded")
    require(
      @semantics.set_text(
        app.editor,
        @semantics.snapshot(app.editor)[1].reference,
        "日本語の描画を確認します ABC 123",
      ) ==
      "",
      "initial editor text rejected",
    )
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
      let mut canceled_id = 0
      let mut update : @async.Task[Unit]? = None
      let mut control_task : @async.Task[Unit]? = None
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
        while !app.closed && app.events.try_get() is Some(event) {
          match event {
            Barrier(applied) => applied.val = true
            Capture(result) =>
              result.val = Some(
                try {
                  let pixels = app.renderer.unwrap().capture_frame()
                  Ok(Captured::{
                    pixels,
                    width: @scene.field(app.state, 6),
                    height: @scene.field(app.state, 7),
                    frame: app.frames,
                  })
                } catch {
                  error => Err(error)
                },
              )
            Edit(text, expected, result) =>
              if expected is Some(revision) &&
                revision != @semantics.revision(app.editor) {
                result.val = Some("stale_revision")
              } else {
                let reference = @semantics.snapshot(app.editor)[1].reference
                let error = match text {
                  Some(text) =>
                    @semantics.replace_selection(app.editor, reference, text)
                  None => @semantics.delete_backward(app.editor, reference)
                }
                if error == "" {
                  app.draw()
                }
                result.val = Some(error)
              }
            StartUpdate => {
              ignore(@task_scope.cancel(app.scope))
              if update is Some(previous) {
                previous.cancel()
                previous.wait() catch {
                  error if @async.is_cancellation_error(error) => ()
                  error => raise error
                }
              }
              let id = @task_scope.begin(app.scope)
              require(id > 0, "update scope unavailable")
              let target = (@scene.field(app.state, 0) - 10).max(0)
              update = Some(
                group.spawn(() => {
                  @async.sleep(250)
                  app.queue(Updated(id, target))
                }),
              )
            }
            CancelUpdate => {
              ignore(@task_scope.cancel(app.scope))
              if update is Some(previous) {
                previous.cancel()
                previous.wait() catch {
                  error if @async.is_cancellation_error(error) => ()
                  error => raise error
                }
              }
              update = None
            }
            Updated(id, value) =>
              if @task_scope.complete(app.scope, id, value) {
                ignore(
                  @scene.move_to(app.state, value, @scene.field(app.state, 1)),
                )
                app.draw()
              } else {
                app.rejected_updates += 1
              }
            Close => {
              app.closed = true
              ignore(@task_scope.dispose(app.scope))
            }
            Resize(size) =>
              if size.width() > 0 && size.height() > 0 {
                if @scene.resize(app.state, size.width(), size.height()) {
                  app.draw()
                }
              }
            Redraw => app.draw()
            Commit(value) => {
              let reference = @semantics.snapshot(app.editor)[1].reference
              require(
                @semantics.replace_selection(app.editor, reference, value) == "",
                "committed text rejected",
              )
              app.draw()
            }
            Backspace => {
              let reference = @semantics.snapshot(app.editor)[1].reference
              require(
                @semantics.delete_backward(app.editor, reference) == "",
                "backspace rejected",
              )
              app.draw()
            }
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
              (app.report)(
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
            if controller is Some(control) {
              control_task = Some(group.spawn(() => control(app.handle())))
            }
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
            let reference = @semantics.snapshot(app.editor)[1].reference
            require(
              @semantics.set_selection(app.editor, reference, 0, 3) == "",
              "test selection rejected",
            )
            app.post(0x0102U, 0x8A9EUL, 0L)
            app.post(0x0102U, 0xD83DUL, 0L)
            app.post(0x0102U, 0xDE00UL, 0L)
          } else if stage == 3 &&
            @semantics.snapshot(app.editor)[1].value ==
            "語😀の描画を確認します ABC 123" {
            let node = @semantics.snapshot(app.editor)[1]
            require(
              node.selection_start == 3 && node.selection_end == 3,
              "committed text caret mismatch",
            )
            require(
              app.rendered_text == Some(node.value),
              "committed text was not rendered",
            )
            stage = 4
            app.post(0x0100U, 0x08UL, 0L)
          } else if stage == 4 &&
            @semantics.snapshot(app.editor)[1].value ==
            "語の描画を確認します ABC 123" {
            require(
              @semantics.snapshot(app.editor)[1].selection_start == 1,
              "backspace caret mismatch",
            )
            stage = 5
            let pixels = app.renderer.unwrap().capture_frame()
            let mut dark = 0
            for y in 8..<104 {
              for x in 8..<309 {
                let offset = (y * 317 + x) * 4
                require(
                  pixels[offset + 3] == 255,
                  "text capture alpha mismatch",
                )
                if pixels[offset] < 128 &&
                  pixels[offset + 1] < 128 &&
                  pixels[offset + 2] < 128 {
                  dark += 1
                }
              }
            }
            require(dark > 100, "text capture has no glyphs")
            let reference = @semantics.snapshot(app.editor)[1].reference
            require(
              @semantics.set_text(app.editor, reference, "") == "",
              "empty text rejected",
            )
            app.draw()
            let empty = app.renderer.unwrap().capture_frame()
            for y in 8..<104 {
              for x in 8..<309 {
                let offset = (y * 317 + x) * 4
                for channel in 0..<4 {
                  require(
                    empty[offset + channel] == 255,
                    "empty text retained glyph pixels",
                  )
                }
              }
            }
            app.post(0x0100U, 0x74UL, 0L)
            app.post(0x0100U, 0x74UL, 0L)
            app.post(0x0102U, 0x41UL, 0L)
          } else if stage == 5 &&
            @semantics.snapshot(app.editor)[1].value == "A" {
            require(
              @task_scope.field(app.scope, 0) == 1,
              "text input did not precede delayed update",
            )
            stage = 6
            app.queue(Updated(@task_scope.field(app.scope, 1) - 1, 0))
          } else if stage == 6 && @task_scope.field(app.scope, 0) == 2 {
            require(
              @scene.field(app.state, 0) == @task_scope.field(app.scope, 2),
              "delayed result did not update scene",
            )
            stage = 7
            require(app.rejected_updates == 1, "stale result was accepted")
            app.post(0x0100U, 0x74UL, 0L)
          } else if stage == 7 && @task_scope.field(app.scope, 0) == 1 {
            canceled_id = @task_scope.field(app.scope, 1)
            stage = 8
            app.post(0x0100U, 0x75UL, 0L)
          } else if stage == 8 && @task_scope.field(app.scope, 0) == 4 {
            stage = 9
            app.queue(Updated(canceled_id, 0))
          } else if stage == 9 && app.rejected_updates == 2 {
            require(
              @scene.field(app.state, 0) == @task_scope.field(app.scope, 2),
              "rejected result changed scene",
            )
            stage = 10
            app.post(0x0100U, 0x74UL, 0L)
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
      ignore(@task_scope.dispose(app.scope))
      if control_task is Some(task) {
        task.cancel()
        task.wait() catch {
          error if @async.is_cancellation_error(error) => ()
          error => raise error
        }
      }
      if update is Some(previous) {
        previous.cancel()
        previous.wait() catch {
          error if @async.is_cancellation_error(error) => ()
          error => raise error
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
        (app.report)(
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
            stage == 10 &&
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
    error => {
      app.closed = true
      ignore(@task_scope.dispose(app.scope))
      app.error = Some(error)
    }
  }
}
