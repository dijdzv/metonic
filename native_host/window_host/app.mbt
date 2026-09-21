///|
extern "C" fn is_window(hwnd : UInt64) -> Int = "IsWindow"

///|
type TaskGate = @host_application.TaskGate

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
#warnings("-unused_constructor")
priv enum InputAction {
  Activate
  Move(Int, Int)
}

///|
// Release keeps an unconstructible-by-public-API slot so the event loop stays shared;
// its payload and handler contain no development operations in that build.
#warnings("-unused_constructor")
priv enum Event {
  Redraw
  Resize(@dpi.PhysicalSize)
  Input(InputAction)
  Commit(String)
  Enter
  CompositionStart
  CompositionUpdate(String, Int?, Bytes)
  CompositionCancel
  CompositionEnd
  Backspace
  Delete
  ApplicationTask(@task.Request, TaskGate)
  ApplicationResult(@task.Completion)
  Development(DevelopmentRequest)
  Accessibility(@accessibility.Request)
  SelectBoundary(Int, Bool)
  Navigate(Bool, Bool)
  NavigateVertical(Bool, Bool)
  ToggleFocus(Bool)
  TextPointer(Int, Int, Bool)
  PointerMove(Int, Int)
  PointerLeave
  Wheel(Int)
  PointerRelease(Int, Int)
  PointerCancel
  Clipboard(@text_clipboard.Action)
  Close
}

///|
struct App {
  event_loop : @windows.EventLoop
  events : @aqueue.Queue[Event]
  hooks : Hooks
  host : @host_application.Application
  clipboard : @text_clipboard.Backend
  diagnostics : Diagnostics
  mut composition : @semantics.Composition?
  mut composition_target : @semantics.NodeRef?
  mut retired_composition : Bool
  ime_pointer : @ime_focus.Transfer
  mut pointer_pressed : Bool
  mut pointer_position : (Int, Int)?
  mut drag : PointerDrag?
  mut preedit : String
  mut preedit_cursor : Int
  mut preedit_attributes : Bytes
  mut control_pressed : Bool
  mut shift_pressed : Bool
  input_navigation : @input_navigation.State
  input_layouts : @input_layout.Registry
  mut presenter : @view_presentation.Presenter?
  hidden : Bool
  minimum_size : (Int, Int)?
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
fn App::default_node(self : App) -> @semantics.Node? {
  guard self.host.default_input is Some(reference) else { return None }
  guard (self.host.view)().inputs.any(input => input.reference == reference) else {
    return None
  }
  match @semantics.node(self.host.editor, reference) {
    Ok(node) if node.role == @semantics.TextInput => Some(node)
    _ => None
  }
}

///|
fn App::input_node(self : App) -> @semantics.Node? {
  let inputs = (self.host.view)().inputs
  let nodes = @semantics.snapshot(self.host.editor)
  for node in nodes {
    if node.role is @semantics.TextInput &&
      node.focused &&
      inputs.any(input => input.reference == node.reference) {
      return Some(node)
    }
  }
  self.default_node()
}

///|
fn App::reconcile_input(self : App) -> Unit {
  if self.drag is Some(drag) {
    let retained = (self.host.view)().inputs.any(input => {
      input.reference == drag.reference
    })
    let eligible = match @semantics.node(self.host.editor, drag.reference) {
      Ok(node) =>
        node.enabled && node.focused && node.role == @semantics.TextInput
      Err(_) => false
    }
    if !retained || !eligible {
      self.cancel_pointer()
    }
  }
  guard self.composition_target is Some(reference) else { return }
  let valid_node = match @semantics.node(self.host.editor, reference) {
    Ok(node) =>
      node.role == @semantics.TextInput && node.enabled && node.focused
    Err(_) => false
  }
  let live = valid_node &&
    (self.host.view)().inputs.any(input => input.reference == reference)
  if !live {
    if self.composition is Some(composition) {
      composition.cancel()
    }
    self.composition = None
    self.composition_target = None
    // The OS may still deliver the retired session's result before its end.
    // Redirecting that untagged text to the new focus would corrupt another input.
    self.retired_composition = true
    self.preedit = ""
    self.preedit_cursor = 0
    self.preedit_attributes = b""
    self.ime_pointer.cancel()
    self.cancel_pointer()
  }
}

///|
pub impl @windows.ApplicationHandler for App with fn can_create_surfaces(
  self,
  event_loop,
) {
  let view = (self.host.view)()
  let attributes = @core.WindowAttributes::default()
    .with_title(view.accessibility.title)
    .with_visible(false)
    .with_inner_size(
      @dpi.PhysicalSize(view.accessibility.width, view.accessibility.height).into_size(),
    )
  let attributes = match self.minimum_size {
    Some((width, height)) =>
      attributes.with_min_inner_size(
        @dpi.PhysicalSize(width, height).into_size(),
      )
    None => attributes
  }
  let window = event_loop.create_window(attributes)
  self.window = Some(window)
  self.hwnd = window.native_window_handle()
  self.accessibility = @accessibility.open(
    self.hwnd,
    @semantics.snapshot(self.host.editor),
    view.accessibility,
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
  self.diagnostics.observe_input(event)
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
    @core.WindowEvent::PointerCanceled(_) => self.queue(PointerCancel)
    @core.WindowEvent::Destroyed => self.queue(PointerCancel)
    @core.WindowEvent::PointerMoved(_, position, _, @core.PointerSource::Mouse) =>
      self.queue(PointerMove(position.x().to_int(), position.y().to_int()))
    @core.WindowEvent::PointerLeft(_, _, _, _) => self.queue(PointerLeave)
    @core.WindowEvent::MouseWheel(_, delta, _) => {
      let pixels = match delta {
        @core.MouseScrollDelta::LineDelta(_, y) => -y * 96.0
        @core.MouseScrollDelta::PixelDelta(position) => -position.y()
      }
      if pixels == pixels {
        self.queue(Wheel(pixels.max(-1048576.0).min(1048576.0).to_int()))
      }
    }
    @core.WindowEvent::PointerButton(
      _,
      @core.ElementState::Released,
      position,
      _,
      @core.ButtonSource::Mouse(@core.MouseButton::Left)
    ) =>
      self.queue(PointerRelease(position.x().to_int(), position.y().to_int()))
    @core.WindowEvent::Ime(@core.Ime::Enabled) => self.queue(CompositionStart)
    @core.WindowEvent::Ime(@core.Ime::Preedit(value, range)) =>
      self.queue(
        CompositionUpdate(value, range.map(cursor => cursor.start()), b""),
      )
    @core.WindowEvent::Ime(
      @core.Ime::PreeditWithAttributes(value, range, attributes)
    ) =>
      self.queue(
        CompositionUpdate(
          value,
          range.map(cursor => cursor.start()),
          attributes,
        ),
      )
    @core.WindowEvent::Ime(@core.Ime::Disabled) => self.queue(CompositionEnd)
    @core.WindowEvent::Ime(@core.Ime::Commit(value)) =>
      if !(value.length() == 1 && value[0].to_int() < 32) {
        self.queue(Commit(value))
      }
    @core.WindowEvent::KeyboardInput(_, key, false) =>
      if key.state() is @core.ElementState::Pressed {
        match key.logical_key() {
          @core.Key::Character("a" | "A") if self.control_pressed =>
            self.queue(SelectBoundary(0, false))
          @core.Key::Character("c" | "C") if self.control_pressed =>
            self.queue(Clipboard(Copy))
          @core.Key::Character("x" | "X") if self.control_pressed =>
            self.queue(Clipboard(Cut))
          @core.Key::Character("v" | "V") if self.control_pressed =>
            self.queue(Clipboard(Paste))
          @core.Key::Named(@core.NamedKey::Home) =>
            self.queue(SelectBoundary(1, self.shift_pressed))
          @core.Key::Named(@core.NamedKey::End) =>
            self.queue(SelectBoundary(2, self.shift_pressed))
          @core.Key::Named(@core.NamedKey::Tab) =>
            self.queue(ToggleFocus(self.shift_pressed))
          @core.Key::Named(@core.NamedKey::Backspace) => self.queue(Backspace)
          @core.Key::Named(@core.NamedKey::Delete) => self.queue(Delete)
          @core.Key::Named(@core.NamedKey::ArrowLeft) =>
            self.queue(Navigate(false, self.shift_pressed))
          @core.Key::Named(@core.NamedKey::ArrowRight) =>
            self.queue(Navigate(true, self.shift_pressed))
          @core.Key::Named(@core.NamedKey::ArrowUp) =>
            self.queue(NavigateVertical(false, self.shift_pressed))
          @core.Key::Named(@core.NamedKey::ArrowDown) =>
            self.queue(NavigateVertical(true, self.shift_pressed))
          @core.Key::Named(@core.NamedKey::Enter) => self.queue(Enter)
          @core.Key::Character(" ") => self.queue(Input(Activate))
          _ =>
            if (self.host.shortcut)(
                key.logical_key(),
                self.control_pressed,
                self.shift_pressed,
              )
              is Some(action) {
              self.queue(ApplicationTask(action.request, action.gate))
            }
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
  self.reconcile_input()
  let view = (self.host.view)()
  if self.renderer is Some(renderer) {
    let presenter = self.presenter.unwrap()
    let input = self.input_node()
    let preedit : @view_presentation.Preedit? = match
      (self.composition, input) {
      (Some(composition), Some(input)) =>
        composition
        .preview(self.preedit)
        .map(text => {
          reference: input.reference,
          text,
          cursor: input.selection_start +
          @ime_presentation.display_cursor(
            self.preedit,
            self.preedit_cursor,
            self.preedit_attributes,
          ),
          ranges: @ime_presentation.target_ranges(
            self.preedit,
            self.preedit_attributes,
          ).map(range => {
            (range.0 + input.selection_start, range.1 + input.selection_start)
          }),
        })
      _ => None
    }
    let rendered = presenter.render(view.items, view.inputs, preedit)
    let layers = match rendered {
      Ok(layers) => layers
      Err(error) => raise WindowFailure::Failure(error)
    }
    if layers is Some(layers) {
      renderer.set_text_layers(
        layers.map(layer => @gpu.TextLayer::{
          x: layer.bounds.x,
          y: layer.bounds.y,
          width: layer.bounds.width,
          height: layer.bounds.height,
          pixels: layer.pixels,
        }),
      )
    }
    if input is Some(input) &&
      presenter.caret_position(input.reference) is Some((x, y)) {
      if self.window is Some(window) {
        window.set_ime_cursor_area(
          @dpi.PhysicalPosition(x, y).into_position(),
          @dpi.PhysicalSize(1, 32).into_size(),
        )
      }
    }
    renderer.present_frame(
      view.accessibility.width,
      view.accessibility.height,
      rectangle=view.rectangle,
      display_scale=self.window.map(window => window.scale_factor()),
    )
    self.diagnostics.presented()
  }
  if self.accessibility is Some(bridge) {
    let nodes = @semantics.snapshot(self.host.editor)
    require(
      bridge.update(
        nodes,
        {
          ..view.accessibility,
          composing: self.composition is Some(_),
          text_scroll: view.accessibility.text_owner
          .map(reference => self.input_layouts.scroll_y(reference))
          .unwrap_or(0),
        },
        view.accessibility.text_owner.bind(reference => {
          self.input_layouts
          .engine(reference)
          .bind(engine => {
            match @semantics.node(self.host.editor, reference) {
              Ok(node) => @raster.text_runs(engine, node.value)
              Err(_) => None
            }
          })
        }),
      ),
      "invalid accessibility presentation",
    )
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
  self.input_layouts.clear()
  self.presenter = None
  self.input_navigation.reset()
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
      match error {
        WindowFailure::Failure(message) =>
          (self.report)("WINDOW_ERROR " + message)
        _ => ()
      }
      raise error
    }
    None => ()
  }
}

///|
async fn run_loop(
  host : @host_application.Application,
  hooks : Hooks,
  hidden : Bool,
  minimum_size : (Int, Int)?,
  font_path : String?,
  report : (String) -> Unit,
  clipboard : @text_clipboard.Backend?,
) -> Unit {
  let event_loop = @windows.EventLoop::new()
  let app : App = {
    event_loop,
    events: @aqueue.Queue::Queue(kind=@aqueue.Blocking(64)),
    hooks,
    host,
    clipboard: clipboard.unwrap_or_else(@platform_clipboard.backend),
    diagnostics: Diagnostics::new(),
    composition: None,
    composition_target: None,
    retired_composition: false,
    ime_pointer: @ime_focus.Transfer::new(),
    pointer_pressed: false,
    pointer_position: None,
    drag: None,
    preedit: "",
    preedit_cursor: 0,
    preedit_attributes: b"",
    control_pressed: false,
    shift_pressed: false,
    input_navigation: @input_navigation.create(host.editor),
    input_layouts: @input_layout.create(host.editor),
    presenter: None,
    hidden,
    minimum_size,
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
    if minimum_size is Some((width, height)) {
      require(width > 0 && height > 0, "minimum client size must be positive")
    }
    app.pump(driver)
    app.message_hwnd = driver.message_window_handle()
    let path = match (font_path, @env.get_env_var("METONIC_FONT_PATH")) {
      (Some(path), _) | (_, Some(path)) => path
      _ => @resources.asset_path("assets/NotoSansJP.ttf")
    }
    let font = @fs.read_file(path).binary() catch {
      error if @async.is_cancellation_error(error) => raise error
      _ =>
        raise WindowFailure::Failure(
          "Unable to read font: " +
          path +
          ". Include assets/NotoSansJP.ttf beside the executable or specify font_path.",
        )
    }
    app.presenter = @view_presentation.create(
      host.editor,
      app.input_layouts,
      app.input_navigation,
      font,
    )
    require(app.presenter is Some(_), "presentation font could not be loaded")
    if (host.initialize)() is Some(action) {
      app.queue(ApplicationTask(action.request, action.gate))
    }
    let window = app.window.unwrap()
    ignore(
      window.request_inner_size(
        @dpi.PhysicalSize(host.initial_size.0, host.initial_size.1).into_size(),
      ),
    )
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
      let tasks = @task_runner.driver()
      defer tasks.close()
      let tasks_running = group.spawn(() => {
        tasks.run(result => app.queue(ApplicationResult(result)), on_state_change=() => {
          app.queue(Redraw)
        })
      })
      let mut control_task : @async.Task[Unit]? = None
      if app.hooks.has_lifecycle() {
        @async.pause()
        may_present = app.hooks.notify(Starting, app)
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
            TextPointer(_, _, _) => {
              app.pointer_pressed = true
              app.drag = None
            }
            Commit(_) if app.ime_pointer.pending() => ()
            Navigate(_, _)
            | NavigateVertical(_, _)
            | SelectBoundary(_, _)
            | ToggleFocus(_)
            | Commit(_)
            | Backspace
            | Delete
            | CompositionStart
            | Close => {
              app.pointer_pressed = false
              app.drag = None
            }
            _ => ()
          }
          app.reconcile_input()
          match event {
            Navigate(_, _)
            | SelectBoundary(_, _)
            | TextPointer(_, _, _)
            | ToggleFocus(_)
            | Commit(_)
            | Backspace
            | Delete
            | CompositionStart => app.input_navigation.reset()
            _ => ()
          }
          match event {
            Navigate(_, _)
            | NavigateVertical(_, _)
            | SelectBoundary(_, _)
            | TextPointer(_, _, _)
            | Commit(_)
            | Backspace
            | Delete
            | CompositionStart =>
              if app.presenter is Some(presenter) &&
                app.input_node() is Some(node) {
                presenter.reveal_input(node.reference)
              }
            _ => ()
          }
          let event = match event {
            Enter if app.composition is None =>
              if app.input_node() is Some(node) &&
                node.focused &&
                app.input_layouts.single_line(node.reference) == Some(false) {
                Commit("\n")
              } else {
                Input(Activate)
              }
            _ => event
          }
          match event {
            Commit(_) | CompositionUpdate(_, _, _) if app.retired_composition =>
              ()
            Commit(_)
            | Backspace
            | Delete
            | CompositionStart
            | CompositionUpdate(_, _, _) if !app
              .input_node()
              .map(node => node.enabled)
              .unwrap_or(false) => ()
            ToggleFocus(_)
            | Navigate(_, _)
            | NavigateVertical(_, _)
            | SelectBoundary(_, _)
            | Accessibility(_)
            | Backspace
            | Delete
            | Input(_)
            | Enter
            | ApplicationTask(_, PointerIdle | CommittedInput) if app.ime_pointer.pending() =>
              ()
            Enter => ()
            Development(request) => app.dispatch_development(request)
            Accessibility(_) if app.composition is Some(_) => ()
            Accessibility(request) => app.apply_accessibility(request)
            SelectBoundary(_, _)
            | Navigate(_, _)
            | NavigateVertical(_, _)
            | ToggleFocus(_) if app.composition is Some(_) => ()
            ToggleFocus(reverse) => {
              move_focus(app.host, reverse)
              app.draw()
            }
            Navigate(_, _) | NavigateVertical(_, _) | SelectBoundary(_, _) if (app.host.navigation_blocked)() =>
              ()
            NavigateVertical(down, extend_selection) =>
              app.navigate_vertical(down, extend_selection)
            Navigate(forward, extend_selection) => {
              if app.input_node() is Some(node) && node.focused {
                ignore(
                  @semantics.navigate(
                    app.host.editor,
                    node.reference,
                    forward,
                    extend_selection,
                  ),
                )
              } else {
                ignore(
                  (app.host.navigate_unhandled)(
                    if forward {
                      10
                    } else {
                      -10
                    },
                    0,
                  ),
                )
              }
              app.draw()
            }
            SelectBoundary(kind, extend_selection) =>
              if app.input_node() is Some(node) {
                ignore(@semantics.focus(app.host.editor, node.reference))
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
                    app.host.editor,
                    node.reference,
                    anchor,
                    end,
                  ),
                )
                app.draw()
              }
            ApplicationTask(_, CommittedInput) if app.composition is Some(_) =>
              ()
            ApplicationTask(request, _) => {
              if !tasks.submit(request) {
                (app.host.input_error)(
                  Some("Application task capacity is full."),
                )
              }
              app.draw()
            }
            ApplicationResult(result) =>
              match result.apply() {
                @task.Changed => app.draw()
                @task.Rejected => app.diagnostics.rejected()
                @task.Unchanged => ()
                @task.Failed(message) => {
                  (app.host.input_error)(Some(message))
                  app.draw()
                }
              }
            Close if app.composition is Some(_) || app.ime_pointer.pending() => {
              (app.host.input_error)(
                Some("Finish or cancel text composition before closing."),
              )
              app.draw()
            }
            Close if !(app.host.can_close)() => {
              (app.host.input_error)(None)
              (app.host.close_requested)()
              app.draw()
            }
            Close => {
              app.closed = true
              app.events.close(clear=true)
              (app.host.stop)()
            }
            Resize(size) =>
              if size.width() > 0 && size.height() > 0 {
                if (app.host.resize)(size.width(), size.height()) {
                  app.draw()
                }
              }
            Redraw => app.draw()
            CompositionStart =>
              if app.composition is None && app.input_node() is Some(node) {
                app.retired_composition = false
                app.composition_target = Some(node.reference)
                app.composition = @semantics.begin_composition(
                  app.host.editor,
                  target=node.reference,
                )
                app.preedit = ""
                app.preedit_cursor = 0
                app.preedit_attributes = b""
                app.draw()
              }
            CompositionUpdate(value, cursor, attributes) => {
              if app.composition is None && app.input_node() is Some(node) {
                app.composition_target = Some(node.reference)
                app.composition = @semantics.begin_composition(
                  app.host.editor,
                  target=node.reference,
                )
              }
              if value != "" && app.composition is Some(composition) {
                if composition.remove_selected_text() is Some(replacement) {
                  app.composition = Some(replacement)
                }
              }
              app.preedit = value
              app.preedit_attributes = attributes
              app.preedit_cursor = cursor
                .unwrap_or(value.length())
                .max(0)
                .min(value.length())
              app.draw()
            }
            CompositionCancel => {
              app.cancel_pointer()
              app.ime_pointer.cancel()
              if app.composition is Some(composition) {
                composition.cancel()
              }
              app.composition = None
              app.composition_target = None
              app.preedit = ""
              app.preedit_attributes = b""
              app.draw()
            }
            CompositionEnd => {
              if app.composition is Some(composition) {
                composition.cancel()
              }
              app.composition = None
              app.composition_target = None
              app.retired_composition = false
              app.preedit = ""
              app.preedit_attributes = b""
              let pointer = app.ime_pointer.finish()
              app.draw()
              if pointer is Some((x, y, extend_selection)) {
                app.apply_pointer(x, y, extend_selection)
              }
            }
            Commit(value) if app.composition is Some(composition) => {
              ignore(composition.commit(value))
              app.composition = None
              app.composition_target = None
              app.preedit = ""
              app.preedit_attributes = b""
              app.draw()
            }
            // Space also arrives as text after scene activation; it must not
            // transfer focus to the editor a second time.
            Commit(" ") if !app
              .input_node()
              .map(node => node.focused)
              .unwrap_or(false) => ()
            Commit(value) =>
              if app.input_node() is Some(node) {
                let reference = node.reference
                ignore(@semantics.focus(app.host.editor, reference))
                require(
                  @semantics.replace_selection(
                    app.host.editor,
                    reference,
                    value,
                  ) ==
                  "",
                  "committed text rejected",
                )
                app.draw()
              }
            Backspace | Delete if app.composition is Some(_) ||
              !app.input_node().map(node => node.focused).unwrap_or(false) => ()
            Backspace =>
              if app.input_node() is Some(node) {
                let reference = node.reference
                require(
                  @semantics.delete_backward(app.host.editor, reference) == "",
                  "backspace rejected",
                )
                app.draw()
              }
            Delete =>
              if app.input_node() is Some(node) {
                require(
                  @semantics.delete_forward(app.host.editor, node.reference) ==
                  "",
                  "forward deletion rejected",
                )
                app.draw()
              }
            TextPointer(x, y, extend_selection) if app.ime_pointer.pending() ||
              app.composition is Some(_) =>
              app.ime_pointer.request(x, y, extend_selection, () => {
                match app.window {
                  Some(window) => window.request_ime_completion()
                  None => false
                }
              })
            TextPointer(x, y, extend_selection) =>
              app.apply_pointer(x, y, extend_selection)
            PointerMove(x, y) => {
              app.pointer_position = Some((x, y))
              app.move_drag(x, y)
            }
            PointerLeave => app.pointer_position = None
            Wheel(delta) => app.scroll_pointer(delta)
            PointerRelease(x, y) => {
              app.move_drag(x, y)
              app.pointer_pressed = false
              app.drag = None
            }
            PointerCancel => app.cancel_pointer()
            Clipboard(action) => app.edit_clipboard(action)
            Input(_) if app.composition is Some(_) => ()
            Input(Activate) => app.activate_focused()
            Input(Move(x, y)) if !app
              .input_node()
              .map(node => node.focused)
              .unwrap_or(false) =>
              if (app.host.navigate_unhandled)(x, y) {
                app.draw()
              }
            Input(_) => ()
          }
          app.hooks.processed(event, app)
          if !app.closed &&
            app.composition is None &&
            !app.ime_pointer.pending() &&
            (app.host.close_ready)() &&
            (app.host.can_close)() {
            app.queue(Close)
          }
          if initializing && app.hooks.has_lifecycle() {
            match event {
              Close => may_present = app.hooks.notify(Closing, app)
              Input(_) | Navigate(_, _) | NavigateVertical(_, _) =>
                may_present = app.hooks.notify(InputHandled, app)
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
            ignore(app.hooks.notify(Ready, app))
            app.draw()
            if app.hooks.has_controller() {
              control_task = Some(group.spawn(() => app.hooks.control(app)))
            }
          }
        }
        if !initializing {
          app.scroll_drag()
          app.hooks.observe(app)
        }
        if initializing && !may_present && app.hooks.has_lifecycle() {
          may_present = app.hooks.notify(Poll, app)
        } else {
          @async.sleep(1)
        }
      }
      (app.host.stop)()
      if control_task is Some(task) {
        task.cancel()
        task.wait() catch {
          error if @async.is_cancellation_error(error) => ()
          error => raise error
        }
      }
      tasks.close()
      tasks_running.wait()
      if initializing {
        init.cancel()
        init.wait() catch {
          error if @async.is_cancellation_error(error) => ()
          error => raise error
        }
      }
      app.hooks.complete(app)
    }
  } catch {
    error => {
      app.closed = true
      app.events.close(clear=true)
      (app.host.stop)()
      app.error = Some(error)
    }
  }
  @async.protect_from_cancel(host.dispose) catch {
    error => if app.error is None { app.error = Some(error) }
  }
}
