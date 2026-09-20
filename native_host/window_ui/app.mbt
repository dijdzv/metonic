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
  Enter
  CompositionStart
  CompositionUpdate(String, Int?, Bytes)
  CompositionCancel
  CompositionEnd
  Backspace
  Delete
  StartUpdate
  LoadUser(String)
  UserLoaded(Int, Result[String, String])
  CancelUpdate
  Updated(Int, Int)
  Development(DevelopmentRequest)
  Accessibility(@accessibility.Request)
  SelectBoundary(Int, Bool)
  Navigate(Bool, Bool)
  NavigateVertical(Bool, Bool)
  ToggleFocus(Bool)
  TextPointer(Int, Int, Bool)
  Close
}

///|
struct App {
  event_loop : @windows.EventLoop
  events : @aqueue.Queue[Event]
  model : @application.Model
  diagnostics : Diagnostics
  mut composition : @semantics.Composition?
  ime_pointer : @ime_focus.Transfer
  mut preedit : String
  mut preedit_cursor : Int
  mut preedit_attributes : Bytes
  mut rendered_preedit_attributes : Bytes
  mut control_pressed : Bool
  mut shift_pressed : Bool
  input_navigation : @input_navigation.State
  input_layouts : @input_layout.Registry
  mut rendered_text : String?
  mut rendered_request_focus : Bool
  mut rendered_task_status : Int
  mut rendered_viewport_height : Int
  mut rendered_control_focus : (Bool, Bool)
  mut rendered_query : (String, Bool, (Int, Int), Int?)
  mut rendered_result : String
  mut rendered_selection : (Int, Int)
  mut rendered_caret : Int?
  mut rendered_active_caret : Int?
  mut rendered_caret_after : Bool
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
fn App::input_node(self : App) -> @semantics.Node {
  let nodes = @semantics.snapshot(self.model.editor)
  for node in nodes {
    if node.role is @semantics.TextInput && node.focused {
      return node
    }
  }
  nodes[1]
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
    @semantics.snapshot(self.model.editor),
    @p0_accessibility.presentation(self.model),
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
          @core.Key::Named(@core.NamedKey::Home) =>
            self.queue(SelectBoundary(1, self.shift_pressed))
          @core.Key::Named(@core.NamedKey::End) =>
            self.queue(SelectBoundary(2, self.shift_pressed))
          @core.Key::Named(@core.NamedKey::Tab) =>
            self.queue(ToggleFocus(self.shift_pressed))
          @core.Key::Named(@core.NamedKey::F5) => self.queue(StartUpdate)
          @core.Key::Named(@core.NamedKey::F7) =>
            self.queue(LoadUser(self.model.query()))
          @core.Key::Named(@core.NamedKey::F6) => self.queue(CancelUpdate)
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
  let display_cursor = @ime_presentation.display_cursor(
    self.preedit,
    self.preedit_cursor,
    self.preedit_attributes,
  )
  let button = @semantics.snapshot(self.model.editor)[0]
  if (button.value == "on") != (@scene.field(self.model.scene, 4) == 1) {
    ignore(@sample.activate(self.model.editor, button.reference))
  }
  match self.renderer {
    Some(renderer) => {
      let node = @semantics.snapshot(self.model.editor)[1]
      let preview = match self.composition {
        Some(composition) if self.input_node().reference == node.reference =>
          composition.preview(self.preedit)
        Some(_) => None
        None => None
      }
      let text = preview.unwrap_or(node.value)
      let selection = if preview is Some(_) {
        (node.selection_start, node.selection_start)
      } else {
        (node.selection_start, node.selection_end)
      }
      let caret = if preview is Some(_) {
        node.selection_start + display_cursor
      } else {
        @semantics.caret(node)
      }
      let targets = @ime_presentation.target_ranges(
        self.preedit,
        self.preedit_attributes,
      ).map(range => {
        (
          range.0 + self.input_node().selection_start,
          range.1 + self.input_node().selection_start,
        )
      })
      let visible_caret = if preview is Some(_) ||
        (node.focused && node.selection_start == node.selection_end) {
        Some(caret)
      } else {
        None
      }
      let view = if self.input_node().reference == self.model.query_input {
        match self.composition {
          Some(composition) =>
            match composition.preview(self.preedit) {
              Some(preview) =>
                self.model.view(
                  query_preview=preview,
                  query_preedit=(
                    self.input_node().selection_start,
                    self.input_node().selection_start,
                    self.input_node().selection_start + display_cursor,
                  ),
                )
              None => self.model.view()
            }
          None => self.model.view()
        }
      } else {
        self.model.view()
      }
      let width = view.editor.bounds.width
      let caret_after = self.editor_caret_after(caret, width)
      let query_active_caret = if view.query.focused &&
        self.composition is Some(_) {
        self.input_node().selection_start + display_cursor
      } else {
        @semantics.caret(@semantics.snapshot(self.model.editor)[5])
      }
      if self.rendered_preedit_attributes != self.preedit_attributes ||
        self.rendered_text != Some(text) ||
        self.rendered_result != self.model.result ||
        self.rendered_request_focus != view.request.focused ||
        self.rendered_task_status != self.model.task_field(0) ||
        self.rendered_viewport_height != @scene.field(self.model.scene, 7) ||
        self.rendered_control_focus != (view.start.focused, view.cancel.focused) ||
        self.rendered_query !=
        (
          view.query.text,
          view.query.focused,
          view.query_selection,
          Some(query_active_caret),
        ) ||
        self.text_width != width ||
        self.rendered_selection != selection ||
        self.rendered_caret != visible_caret ||
        self.rendered_active_caret != Some(caret) ||
        self.rendered_caret_after != caret_after {
        let query_width = (view.query.bounds.width - 16).max(1)
        require(
          self.input_layouts.prepare_single_line(
            self.model.query_input,
            view.query.text,
            query_width,
            if view.query.focused {
              Some(query_active_caret)
            } else {
              None
            },
          ),
          "single-line input layout unavailable",
        )
        let layers = @view_renderer.render(
          self.input_layouts.engine(self.model.editor_input).unwrap(),
          view,
          text,
          selection~,
          selection_ranges?=if preview is Some(_) {
            Some(targets)
          } else {
            None
          },
          query_selection_ranges?=if self.composition is Some(composition) &&
            self.input_node().reference == self.model.query_input &&
            composition.preview(self.preedit) is Some(_) {
            Some(targets)
          } else {
            None
          },
          caret=visible_caret,
          caret_after~,
          query_scroll=Some(self.input_layouts.scroll_x(self.model.query_input)),
          editor_scroll=self.input_layouts.scroll_y(self.model.editor_input),
          editor_active_caret=Some(caret),
        )
        require(
          self.input_layouts.sync_vertical_scroll(self.model.editor_input),
          "multiline input layout unavailable",
        )
        renderer.set_text_layers(
          layers.map(layer => @gpu.TextLayer::{
            x: layer.bounds.x,
            y: layer.bounds.y,
            width: layer.bounds.width,
            height: layer.bounds.height,
            pixels: layer.pixels,
          }),
        )
        self.rendered_preedit_attributes = self.preedit_attributes
        self.rendered_request_focus = view.request.focused
        self.rendered_task_status = self.model.task_field(0)
        self.rendered_viewport_height = @scene.field(self.model.scene, 7)
        self.rendered_control_focus = (view.start.focused, view.cancel.focused)
        self.rendered_query = (
          view.query.text,
          view.query.focused,
          view.query_selection,
          Some(query_active_caret),
        )
        self.rendered_text = Some(text)
        self.rendered_result = self.model.result
        self.rendered_selection = selection
        self.rendered_caret = visible_caret
        self.rendered_active_caret = Some(caret)
        self.rendered_caret_after = caret_after
        self.text_width = width
      }
      let query_focused = view.query.focused
      let input_caret = if query_focused {
        if self.composition is Some(_) {
          self.input_node().selection_start + display_cursor
        } else {
          @semantics.caret(self.input_node())
        }
      } else {
        caret
      }
      let position = @raster.caret_position(
        if query_focused {
          self.input_layouts.engine(self.model.query_input).unwrap()
        } else {
          self.input_layouts.engine(self.model.editor_input).unwrap()
        },
        input_caret,
        after=if query_focused { false } else { caret_after },
      )
      if position is Some((x, y)) {
        if self.window is Some(window) {
          window.set_ime_cursor_area(
            @dpi.PhysicalPosition(
              x +
              (if query_focused {
                view.query.bounds.x +
                8 -
                self.input_layouts.scroll_x(self.model.query_input)
              } else {
                8
              }),
              y +
              (if query_focused {
                view.query.bounds.y + 2
              } else {
                8 - self.input_layouts.scroll_y(self.model.editor_input)
              }),
            ).into_position(),
            @dpi.PhysicalSize(1, 32).into_size(),
          )
        }
      }
      renderer.present(
        @scene.field(self.model.scene, 6),
        @scene.field(self.model.scene, 7),
        @scene.field(self.model.scene, 0),
        @scene.field(self.model.scene, 1),
        @scene.field(self.model.scene, 2),
        @scene.field(self.model.scene, 3),
        @scene.field(self.model.scene, 4),
        display_scale=self.window.map(window => window.scale_factor()),
      )
      self.diagnostics.presented()
    }
    None => ()
  }
  if self.accessibility is Some(bridge) {
    let nodes = @semantics.snapshot(self.model.editor)
    require(
      bridge.update(
        nodes,
        @p0_accessibility.presentation(
          self.model,
          composing=self.composition is Some(_),
          editor_scroll=self.input_layouts.scroll_y(self.model.editor_input),
        ),
        self.input_layouts
        .engine(self.model.editor_input)
        .bind(engine => @raster.text_runs(engine, nodes[1].value)),
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
  let model = @application.create(1, 1)
  let app : App = {
    event_loop,
    events: @aqueue.Queue::Queue(kind=@aqueue.Blocking(64)),
    model,
    diagnostics: Diagnostics::new(),
    composition: None,
    ime_pointer: @ime_focus.Transfer::new(),
    preedit: "",
    preedit_cursor: 0,
    preedit_attributes: b"",
    rendered_preedit_attributes: b"",
    control_pressed: false,
    shift_pressed: false,
    input_navigation: @input_navigation.create(model.editor),
    input_layouts: @input_layout.create(model.editor),
    rendered_text: None,
    rendered_result: "",
    rendered_request_focus: false,
    rendered_task_status: -1,
    rendered_viewport_height: -1,
    rendered_control_focus: (false, false),
    rendered_query: ("", false, (0, 0), None),
    rendered_selection: (-1, -1),
    rendered_caret: None,
    rendered_active_caret: None,
    rendered_caret_after: false,
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
    let font = @fs.read_file(
      @env.get_env_var("METONIC_FONT_PATH").unwrap_or(
        ".work/text-assets/NotoSansJP.ttf",
      ),
    ).binary()
    require(
      app.input_layouts.register(model.editor_input, font, false),
      "font could not be loaded",
    )
    require(
      app.input_layouts.register(model.query_input, font, true),
      "query font could not be loaded",
    )
    require(
      @semantics.set_text(
        app.model.editor,
        @semantics.snapshot(app.model.editor)[1].reference,
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
          let event = match event {
            Enter if app.composition is None => {
              let node = app.input_node()
              if node.focused && node.reference != app.model.query_input {
                Commit("\n")
              } else {
                Input(Activate)
              }
            }
            _ => event
          }
          match event {
            ToggleFocus(_)
            | Navigate(_, _)
            | NavigateVertical(_, _)
            | SelectBoundary(_, _)
            | Accessibility(_)
            | Backspace
            | Delete
            | Input(_)
            | Enter
            | StartUpdate
            | LoadUser(_) if app.ime_pointer.pending() => ()
            Enter => ()
            Development(request) => app.dispatch_development(request)
            Accessibility(_) if app.composition is Some(_) => ()
            Accessibility(request) => {
              let nodes = @semantics.snapshot(app.model.editor)
              match request {
                @accessibility.Focus(target) => {
                  if app.window is Some(window) {
                    window.focus_window()
                  }
                  ignore(
                    @semantics.focus(
                      app.model.editor,
                      nodes[target - 1].reference,
                    ),
                  )
                  app.draw()
                }
                @accessibility.Click(target) if target ==
                  app.model.request_button.id => {
                  ignore(app.model.focus_request())
                  app.queue(LoadUser(app.model.query()))
                  app.draw()
                }
                @accessibility.Click(target) if target ==
                  app.model.start_button.id ||
                  target == app.model.cancel_button.id => {
                  ignore(
                    @semantics.focus(
                      app.model.editor,
                      nodes[target - 1].reference,
                    ),
                  )
                  app.queue(
                    if target == app.model.start_button.id {
                      StartUpdate
                    } else {
                      CancelUpdate
                    },
                  )
                }
                @accessibility.Click(1) => {
                  ignore(@scene.dispatch(app.model.scene, Activate))
                  app.draw()
                }
                @accessibility.SetValue(target, text) if target == 2 ||
                  target == app.model.query_input.id =>
                  if @semantics.set_text(
                      app.model.editor,
                      nodes[target - 1].reference,
                      text,
                    ) ==
                    "" {
                    app.draw()
                  }
                @accessibility.Select(_, _, _, _) =>
                  if app.accessibility is Some(bridge) {
                    if bridge.resolve_selection(request)
                      is Some((anchor, caret)) {
                      ignore(
                        @semantics.focus(app.model.editor, nodes[1].reference),
                      )
                      ignore(
                        @semantics.set_selection_directed(
                          app.model.editor,
                          nodes[1].reference,
                          anchor,
                          caret,
                        ),
                      )
                      app.draw()
                    }
                  }
                _ => ()
              }
            }
            SelectBoundary(_, _)
            | Navigate(_, _)
            | NavigateVertical(_, _)
            | ToggleFocus(_) if app.composition is Some(_) => ()
            ToggleFocus(reverse) => {
              move_focus(app.model, reverse)
              app.draw()
            }
            Navigate(_, _) | NavigateVertical(_, _) | SelectBoundary(_, _) if app.model.control_focused() =>
              ()
            NavigateVertical(down, extend_selection) =>
              app.navigate_vertical(down, extend_selection)
            Navigate(forward, extend_selection) => {
              let node = app.input_node()
              if node.focused {
                ignore(
                  @semantics.navigate(
                    app.model.editor,
                    node.reference,
                    forward,
                    extend_selection,
                  ),
                )
              } else {
                ignore(
                  @scene.dispatch(
                    app.model.scene,
                    Move(if forward { 10 } else { -10 }, 0),
                  ),
                )
              }
              app.draw()
            }
            SelectBoundary(kind, extend_selection) => {
              let node = app.input_node()
              ignore(@semantics.focus(app.model.editor, node.reference))
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
                  app.model.editor,
                  node.reference,
                  anchor,
                  end,
                ),
              )
              app.draw()
            }
            LoadUser(_) if app.composition is Some(_) => ()
            StartUpdate | LoadUser(_) => {
              let user_id = match event {
                LoadUser(value) => Some(value)
                _ => None
              }
              ignore(app.model.cancel_update())
              if update is Some(previous) {
                previous.cancel()
                previous.wait() catch {
                  error if @async.is_cancellation_error(error) => ()
                  error => raise error
                }
              }
              let id = app.model.begin_update()
              require(id > 0, "update scope unavailable")
              let target = app.model.movement_target()
              app.draw()
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
                    let result = @clock.after(RealClock::{ }, 1000, target)
                    app.queue(Updated(id, result))
                  }
                }),
              )
            }
            CancelUpdate => {
              ignore(app.model.cancel_update())
              if update is Some(previous) {
                previous.cancel()
                previous.wait() catch {
                  error if @async.is_cancellation_error(error) => ()
                  error => raise error
                }
              }
              update = None
              app.draw()
            }
            UserLoaded(id, result) =>
              if app.model.complete_user(id, result) {
                app.draw()
              }
            Updated(id, value) =>
              if app.model.complete_movement(id, value) {
                app.draw()
              } else {
                app.diagnostics.rejected()
              }
            Close => {
              app.closed = true
              app.events.close(clear=true)
              ignore(app.model.stop())
            }
            Resize(size) =>
              if size.width() > 0 && size.height() > 0 {
                if @scene.resize(app.model.scene, size.width(), size.height()) {
                  app.draw()
                }
              }
            Redraw => app.draw()
            CompositionStart =>
              if app.composition is None {
                app.composition = @semantics.begin_composition(
                  app.model.editor,
                  target=app.input_node().reference,
                )
                app.preedit = ""
                app.preedit_cursor = 0
                app.preedit_attributes = b""
                app.draw()
              }
            CompositionUpdate(value, cursor, attributes) => {
              if app.composition is None {
                app.composition = @semantics.begin_composition(
                  app.model.editor,
                  target=app.input_node().reference,
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
              app.ime_pointer.cancel()
              if app.composition is Some(composition) {
                composition.cancel()
              }
              app.composition = None
              app.preedit = ""
              app.preedit_attributes = b""
              app.draw()
            }
            CompositionEnd => {
              if app.composition is Some(composition) {
                composition.cancel()
              }
              app.composition = None
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
              app.preedit = ""
              app.preedit_attributes = b""
              app.draw()
            }
            // Space also arrives as text after scene activation; it must not
            // transfer focus to the editor a second time.
            Commit(" ") if !app.input_node().focused => ()
            Commit(value) => {
              let reference = app.input_node().reference
              ignore(@semantics.focus(app.model.editor, reference))
              require(
                @semantics.replace_selection(app.model.editor, reference, value) ==
                "",
                "committed text rejected",
              )
              app.draw()
            }
            Backspace | Delete if app.composition is Some(_) ||
              !app.input_node().focused => ()
            Backspace => {
              let reference = app.input_node().reference
              require(
                @semantics.delete_backward(app.model.editor, reference) == "",
                "backspace rejected",
              )
              app.draw()
            }
            Delete => {
              require(
                @semantics.delete_forward(
                  app.model.editor,
                  app.input_node().reference,
                ) ==
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
            Input(Activate) if app.model.request_focused() &&
              app.composition is None => app.queue(LoadUser(app.model.query()))
            Input(Activate) if app.model.control_focused() &&
              app.composition is None =>
              app.queue(
                if app.model.view().start.focused {
                  StartUpdate
                } else {
                  CancelUpdate
                },
              )
            Input(_) if app.composition is Some(_) ||
              app.model.control_focused() ||
              app.input_node().focused => ()
            Input(action) =>
              if @scene.dispatch(app.model.scene, action) {
                app.draw()
              }
          }
          hooks.processed(event, app)
          if initializing && hooks.has_lifecycle() {
            match event {
              Close => may_present = hooks.notify(Closing, app)
              Input(_) | Navigate(_, _) | NavigateVertical(_, _) =>
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
      ignore(app.model.stop())
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
      app.events.close(clear=true)
      ignore(app.model.stop())
      app.error = Some(error)
    }
  }
}

///|
fn App::apply_pointer(
  app : App,
  x : Int,
  y : Int,
  extend_selection : Bool,
) -> Unit raise {
  match (x, y, extend_selection) {
    (x, y, extend_selection) if app.model.view().query.bounds.contains(x, y) => {
      ignore(@semantics.focus(app.model.editor, app.model.query_input))
      let node = app.input_node()
      let box = app.model.view().query.bounds
      if app.input_layouts.engine(app.model.query_input) is Some(engine) {
        if @raster.hit(
            engine,
            (x - box.x - 8).max(0) +
            app.input_layouts.scroll_x(app.model.query_input),
            (y - box.y - 2).max(0),
          )
          is Some(offset) {
          let caret = offset.min(node.value.length())
          ignore(
            @semantics.set_selection_directed(
              app.model.editor,
              node.reference,
              if extend_selection {
                node.selection_anchor
              } else {
                caret
              },
              caret,
            ),
          )
        }
      }
      app.draw()
    }
    (x, y, _) if app.model.view().start.bounds.contains(x, y) ||
      app.model.view().cancel.bounds.contains(x, y) => {
      let start = app.model.view().start.bounds.contains(x, y)
      ignore(
        @semantics.focus(
          app.model.editor,
          if start {
            app.model.start_button
          } else {
            app.model.cancel_button
          },
        ),
      )
      app.queue(if start { StartUpdate } else { CancelUpdate })
    }
    (x, y, _) if app.model.view().request.bounds.contains(x, y) &&
      app.composition is None => {
      ignore(app.model.focus_request())
      app.queue(LoadUser(app.model.query()))
      app.draw()
    }
    (x, y, extend_selection) =>
      if x >= 8 && x < 8 + app.text_width && y >= 8 && y < 104 {
        if app.input_layouts.engine(app.model.editor_input) is Some(engine) {
          if @raster.hit_caret(
              engine,
              x - 8,
              y - 8 + app.input_layouts.scroll_y(app.model.editor_input),
            )
            is Some((offset, after)) {
            let node = @semantics.snapshot(app.model.editor)[1]
            ignore(@semantics.focus(app.model.editor, node.reference))
            let caret = offset.min(node.value.length())
            let anchor = if extend_selection {
              node.selection_anchor
            } else {
              caret
            }
            ignore(
              @semantics.set_selection_directed(
                app.model.editor,
                node.reference,
                anchor,
                caret,
              ),
            )
            ignore(
              app.input_navigation.remember(
                node.reference,
                caret,
                app.text_width,
                after,
                None,
              ),
            )
            app.draw()
          }
        }
      } else {
        ignore(
          @semantics.focus(
            app.model.editor,
            @semantics.snapshot(app.model.editor)[0].reference,
          ),
        )
        ignore(@scene.dispatch(app.model.scene, Click(x, y)))
        app.draw()
      }
  }
}
