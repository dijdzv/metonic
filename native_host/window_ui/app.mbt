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
// Release keeps an unconstructible-by-public-API slot so the event loop stays shared;
// its payload and handler contain no development operations in that build.
#warnings("-unused_constructor")
priv enum Event {
  Redraw
  Resize(@dpi.PhysicalSize)
  Input(@scene.Action)
  Commit(String)
  CompositionStart
  CompositionUpdate(String, Int?)
  CompositionCancel
  Backspace
  StartUpdate
  LoadUser(String)
  UserLoaded(Int, Result[String, String])
  CancelUpdate
  Updated(Int, Int)
  Development(DevelopmentRequest)
  Accessibility(@accessibility.Request)
  SelectBoundary(Int, Bool)
  Navigate(Bool, Bool)
  ToggleFocus
  TextPointer(Int, Int, Bool)
  Close
}

///|
struct App {
  event_loop : @windows.EventLoop
  events : @aqueue.Queue[Event]
  state : @scene.State
  editor : @semantics.Tree
  scope : @task_scope.Scope
  diagnostics : Diagnostics
  mut rpc_result : String
  mut composition : @semantics.Composition?
  mut preedit : String
  mut preedit_cursor : Int
  mut control_pressed : Bool
  mut shift_pressed : Bool
  mut raster : @raster.Engine?
  mut rendered_text : String?
  mut rendered_selection : (Int, Int)
  mut rendered_caret : Int?
  mut text_width : Int
  hidden : Bool
  report : (String) -> Unit
  mut window : @windows.Window?
  mut accessibility : @accessibility.Bridge?
  mut error : Error?
  mut hwnd : UInt64
  mut message_hwnd : UInt64
  mut instance : @wgpu.Instance?
  mut surface : @wgpu.Surface?
  owner : @gpu.Initialization
  mut renderer : @gpu.SurfaceRenderer?
  mut closed : Bool
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
    .with_title("Metonic")
    .with_visible(false)
    .with_inner_size(@dpi.PhysicalSize(640, 360).into_size()),
  )
  self.window = Some(window)
  self.hwnd = window.native_window_handle()
  self.accessibility = @accessibility.open(
    self.hwnd,
    @semantics.snapshot(self.editor),
  )
  if self.accessibility is None {
    self.error = Some(WindowFailure::Failure("accessibility attachment failed"))
    self.queue(Close)
  } else {
    window.set_visible(!self.hidden)
  }
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
    @core.WindowEvent::ModifiersChanged(modifiers) => {
      self.control_pressed = modifiers.control_key()
      self.shift_pressed = modifiers.shift_key()
    }
    @core.WindowEvent::Focused(false) => {
      self.control_pressed = false
      self.shift_pressed = false
      self.queue(CompositionCancel)
    }
    @core.WindowEvent::Ime(@core.Ime::Enabled) => self.queue(CompositionStart)
    @core.WindowEvent::Ime(@core.Ime::Preedit(value, range)) =>
      self.queue(CompositionUpdate(value, range.map(cursor => cursor.start())))
    @core.WindowEvent::Ime(@core.Ime::Disabled) => self.queue(CompositionCancel)
    @core.WindowEvent::Ime(@core.Ime::Commit(value)) =>
      if !(value.length() == 1 && value[0].to_int() < 32) {
        self.queue(Commit(value))
      }
    @core.WindowEvent::KeyboardInput(_, key, false) =>
      if key.state() is @core.ElementState::Pressed {
        match key.logical_key() {
          @core.Key::Character("a" | "A") if self.control_pressed =>
            self.queue(SelectBoundary(0, false))
          @core.Key::Named(@core.NamedKey::Home) =>
            self.queue(SelectBoundary(1, self.shift_pressed))
          @core.Key::Named(@core.NamedKey::End) =>
            self.queue(SelectBoundary(2, self.shift_pressed))
          @core.Key::Named(@core.NamedKey::Tab) => self.queue(ToggleFocus)
          @core.Key::Named(@core.NamedKey::F5) => self.queue(StartUpdate)
          @core.Key::Named(@core.NamedKey::F7) => self.queue(LoadUser("1"))
          @core.Key::Named(@core.NamedKey::F6) => self.queue(CancelUpdate)
          @core.Key::Named(@core.NamedKey::Backspace) => self.queue(Backspace)
          @core.Key::Named(@core.NamedKey::ArrowLeft) =>
            self.queue(Navigate(false, self.shift_pressed))
          @core.Key::Named(@core.NamedKey::ArrowRight) =>
            self.queue(Navigate(true, self.shift_pressed))
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
    ) =>
      self.queue(
        TextPointer(
          position.x().to_int(),
          position.y().to_int(),
          self.shift_pressed,
        ),
      )
    _ => ()
  }
}

///|
fn App::draw(self : App) -> Unit raise Error {
  let button = @semantics.snapshot(self.editor)[0]
  if (button.value == "on") != (@scene.field(self.state, 4) == 1) {
    ignore(@semantics.activate(self.editor, button.reference))
  }
  if self.accessibility is Some(bridge) {
    bridge.update(
      @semantics.snapshot(self.editor),
      @scene.field(self.state, 6),
      @scene.field(self.state, 7),
      @scene.field(self.state, 0),
      @scene.field(self.state, 1),
      self.composition is Some(_),
      self.rpc_result,
    )
  }
  match self.renderer {
    Some(renderer) => {
      let node = @semantics.snapshot(self.editor)[1]
      let preview = match self.composition {
        Some(composition) => composition.preview(self.preedit)
        None => None
      }
      let text = preview.unwrap_or(node.value) + self.rpc_result
      let selection = if preview is Some(_) {
        (node.selection_start, node.selection_start + self.preedit.length())
      } else {
        (node.selection_start, node.selection_end)
      }
      let caret = if preview is Some(_) {
        node.selection_start + self.preedit_cursor
      } else {
        @semantics.caret(node)
      }
      let visible_caret = if preview is Some(_) ||
        (node.focused && node.selection_start == node.selection_end) {
        Some(caret)
      } else {
        None
      }
      let width = (@scene.field(self.state, 6) - 16).max(1).min(640)
      if self.rendered_text != Some(text) ||
        self.text_width != width ||
        self.rendered_selection != selection ||
        self.rendered_caret != visible_caret {
        let pixels = @raster.render(
          self.raster.unwrap(),
          text,
          width,
          96,
          selection~,
          caret=visible_caret,
        )
        renderer.set_text_pixels(width, 96, pixels)
        self.rendered_text = Some(text)
        self.rendered_selection = selection
        self.rendered_caret = visible_caret
        self.text_width = width
      }
      if @raster.caret_position(self.raster.unwrap(), caret) is Some((x, y)) {
        if self.window is Some(window) {
          window.set_ime_cursor_area(
            @dpi.PhysicalPosition(x + 8, y + 8).into_position(),
            @dpi.PhysicalSize(1, 32).into_size(),
          )
        }
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
      self.diagnostics.presented()
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
fn App::finish(self : App) -> Unit raise Error {
  if self.accessibility is Some(bridge) {
    bridge.close()
  }
  self.accessibility = None
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
    None => ()
  }
}

///|
async fn run_loop(
  hooks : Hooks,
  hidden : Bool,
  report : (String) -> Unit,
) -> Unit {
  let event_loop = @windows.EventLoop::new()
  let app : App = {
    event_loop,
    events: @aqueue.Queue::Queue(kind=@aqueue.Blocking(64)),
    state: @scene.create(),
    editor: @semantics.create(1, 1),
    scope: @task_scope.create(),
    diagnostics: Diagnostics::new(),
    rpc_result: "",
    composition: None,
    preedit: "",
    preedit_cursor: 0,
    control_pressed: false,
    shift_pressed: false,
    raster: None,
    rendered_text: None,
    rendered_selection: (-1, -1),
    rendered_caret: None,
    text_width: 0,
    hidden,
    report,
    window: None,
    accessibility: None,
    error: None,
    hwnd: 0UL,
    message_hwnd: 0UL,
    instance: None,
    surface: None,
    owner: @gpu.Initialization::new(),
    renderer: None,
    closed: false,
  }
  let driver = @loop.Driver::new(
    event_loop,
    app as &@windows.ApplicationHandler,
    _ => app.finish(),
  )
  @async.set_external_event_loop(driver)
  event_loop.set_control_flow(@core.ControlFlow::Wait)
  try {
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
      let mut may_present = true
      let mut update : @async.Task[Unit]? = None
      let mut control_task : @async.Task[Unit]? = None
      if hooks.has_lifecycle() {
        @async.pause()
        may_present = hooks.notify(Starting, app)
      }
      while !app.closed {
        app.pump(driver)
        if app.accessibility is Some(bridge) {
          for request in bridge.poll() {
            app.queue(Accessibility(request))
          }
        }
        while !app.closed && app.events.try_get() is Some(event) {
          match event {
            Development(request) => app.dispatch_development(request)
            Accessibility(_) if app.composition is Some(_) => ()
            Accessibility(request) => {
              let nodes = @semantics.snapshot(app.editor)
              match request {
                @accessibility.Focus(target) => {
                  if app.window is Some(window) {
                    window.focus_window()
                  }
                  ignore(
                    @semantics.focus(app.editor, nodes[target - 1].reference),
                  )
                  app.draw()
                }
                @accessibility.Click(1) => {
                  ignore(@scene.dispatch(app.state, Activate))
                  app.draw()
                }
                @accessibility.SetValue(2, text) =>
                  if @semantics.set_text(app.editor, nodes[1].reference, text) ==
                    "" {
                    app.draw()
                  }
                _ => ()
              }
            }
            SelectBoundary(_, _) | Navigate(_, _) | ToggleFocus if app.composition
              is Some(_) => ()
            ToggleFocus => {
              let nodes = @semantics.snapshot(app.editor)
              let target = if nodes[1].focused { nodes[0] } else { nodes[1] }
              ignore(@semantics.focus(app.editor, target.reference))
              app.draw()
            }
            Navigate(forward, extend_selection) => {
              let node = @semantics.snapshot(app.editor)[1]
              if node.focused {
                ignore(
                  @semantics.navigate(
                    app.editor,
                    node.reference,
                    forward,
                    extend_selection,
                  ),
                )
              } else {
                ignore(
                  @scene.dispatch(
                    app.state,
                    Move(if forward { 10 } else { -10 }, 0),
                  ),
                )
              }
              app.draw()
            }
            SelectBoundary(kind, extend_selection) => {
              let node = @semantics.snapshot(app.editor)[1]
              ignore(@semantics.focus(app.editor, node.reference))
              let end = if kind == 1 { 0 } else { node.value.length() }
              let anchor = if kind == 0 {
                0
              } else if extend_selection {
                node.selection_anchor
              } else {
                end
              }
              ignore(
                @semantics.set_selection_directed(
                  app.editor,
                  node.reference,
                  anchor,
                  end,
                ),
              )
              app.draw()
            }
            StartUpdate | LoadUser(_) => {
              let user_id = match event {
                LoadUser(value) => Some(value)
                _ => None
              }
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
                  if user_id is Some(value) {
                    let result = @rpc_client.get_user(
                      @env.get_env_var("METONIC_RPC_BASE").unwrap_or(
                        "http://127.0.0.1:4174",
                      ),
                      value,
                    )
                    app.queue(UserLoaded(id, result.map(user => user.name)))
                  } else {
                    @async.sleep(250)
                    app.queue(Updated(id, target))
                  }
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
            UserLoaded(id, result) =>
              match result {
                Ok(name) =>
                  if @task_scope.complete(app.scope, id, 0) {
                    app.rpc_result = "\n" + name
                    app.draw()
                  }
                Err(error) =>
                  if @task_scope.fail(app.scope, id, 1) {
                    app.rpc_result = "\nRPC: " + error
                    app.draw()
                  }
              }
            Updated(id, value) =>
              if @task_scope.complete(app.scope, id, value) {
                ignore(
                  @scene.move_to(app.state, value, @scene.field(app.state, 1)),
                )
                app.draw()
              } else {
                app.diagnostics.rejected()
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
            CompositionStart =>
              if app.composition is None {
                app.composition = @semantics.begin_composition(app.editor)
                app.preedit = ""
                app.draw()
              }
            CompositionUpdate(value, cursor) => {
              if app.composition is None {
                app.composition = @semantics.begin_composition(app.editor)
              }
              app.preedit = value
              app.preedit_cursor = cursor
                .unwrap_or(value.length())
                .max(0)
                .min(value.length())
              app.draw()
            }
            CompositionCancel => {
              if app.composition is Some(composition) {
                composition.cancel()
              }
              app.composition = None
              app.preedit = ""
              app.draw()
            }
            Commit(value) if app.composition is Some(composition) => {
              ignore(composition.commit(value))
              app.composition = None
              app.preedit = ""
              app.draw()
            }
            // Space also arrives as text after scene activation; it must not
            // transfer focus to the editor a second time.
            Commit(" ") if !@semantics.snapshot(app.editor)[1].focused => ()
            Commit(value) => {
              let reference = @semantics.snapshot(app.editor)[1].reference
              ignore(@semantics.focus(app.editor, reference))
              require(
                @semantics.replace_selection(app.editor, reference, value) == "",
                "committed text rejected",
              )
              app.draw()
            }
            Backspace if app.composition is Some(_) ||
              !@semantics.snapshot(app.editor)[1].focused => ()
            Backspace => {
              let reference = @semantics.snapshot(app.editor)[1].reference
              require(
                @semantics.delete_backward(app.editor, reference) == "",
                "backspace rejected",
              )
              app.draw()
            }
            TextPointer(_, _, _) if app.composition is Some(_) => ()
            TextPointer(x, y, extend_selection) =>
              if x >= 8 && x < 8 + app.text_width && y >= 8 && y < 104 {
                if app.raster is Some(engine) {
                  if @raster.hit(engine, x - 8, y - 8) is Some(offset) {
                    let node = @semantics.snapshot(app.editor)[1]
                    ignore(@semantics.focus(app.editor, node.reference))
                    let caret = offset.min(node.value.length())
                    let anchor = if extend_selection {
                      node.selection_anchor
                    } else {
                      caret
                    }
                    ignore(
                      @semantics.set_selection_directed(
                        app.editor,
                        node.reference,
                        anchor,
                        caret,
                      ),
                    )
                    app.draw()
                  }
                }
              } else {
                ignore(
                  @semantics.focus(
                    app.editor,
                    @semantics.snapshot(app.editor)[0].reference,
                  ),
                )
                ignore(@scene.dispatch(app.state, Click(x, y)))
                app.draw()
              }
            Input(_) if app.composition is Some(_) ||
              @semantics.snapshot(app.editor)[1].focused => ()
            Input(action) =>
              if @scene.dispatch(app.state, action) {
                app.draw()
              }
          }
          if initializing && hooks.has_lifecycle() {
            match event {
              Close => may_present = hooks.notify(Closing, app)
              Input(_) | Navigate(_, _) =>
                may_present = hooks.notify(InputHandled, app)
              _ => ()
            }
          }
        }
        if app.closed {
          break
        }
        if initializing && may_present {
          if init.try_wait() is Some(_) {
            init.wait()
            initializing = false
            ignore(hooks.notify(Ready, app))
            app.draw()
            if hooks.has_controller() {
              control_task = Some(group.spawn(() => hooks.control(app)))
            }
          }
        }
        if !initializing {
          hooks.observe(app)
        }
        if initializing && !may_present && hooks.has_lifecycle() {
          may_present = hooks.notify(Poll, app)
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
      hooks.complete(app)
    }
  } catch {
    error => {
      app.closed = true
      ignore(@task_scope.dispose(app.scope))
      app.error = Some(error)
    }
  }
}
