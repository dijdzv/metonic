///|
pub using @p0_tasks {movement, user, cancel, movement_result}

///|
pub fn scene_field(model : @application.Model, index : Int) -> Int {
  @scene.field(model.scene, index)
}

///|
pub fn create(model : @application.Model) -> @host.Application {
  {
    editor: model.editor,
    default_input: Some(model.editor_input),
    connect_tasks: _ => (),
    initialize: () => {
      ignore(
        @semantics.set_text(
          model.editor,
          model.editor_input,
          "日本語の描画を確認します ABC 123",
        ),
      )
      None
    },
    initial_size: (640, 360),
    view: () => {
      let button = @semantics.snapshot(model.editor)[0]
      if (button.value == "on") != (@scene.field(model.scene, 4) == 1) {
        ignore(@sample.activate(model.editor, button.reference))
      }
      let view = model.view()
      {
        items: @view_renderer.items(view, view.editor.text),
        inputs: [
          { reference: model.editor_input, single_line: false, },
          { reference: model.query_input, single_line: true, },
        ],
        rectangle: Some({
          x: @scene.field(model.scene, 0),
          y: @scene.field(model.scene, 1),
          width: @scene.field(model.scene, 2),
          height: @scene.field(model.scene, 3),
          active: @scene.field(model.scene, 4),
        }),
        accessibility: @p0_accessibility.presentation(model),
      }
    },
    focus_order: () => {
      let nodes = @semantics.snapshot(model.editor)
      let order = [model.editor_input, nodes[0].reference]
      for i = 2; i < nodes.length(); i = i + 1 {
        order.push(nodes[i].reference)
      }
      order
    },
    activate: reference => {
      if reference == model.request_button {
        ignore(model.focus_request())
        Some({
          request: @p0_tasks.user(model, model.query()),
          gate: @host.CommittedInput,
        })
      } else if reference == model.start_button {
        Some({ request: @p0_tasks.movement(model), gate: @host.PointerIdle, })
      } else if reference == model.cancel_button {
        Some({ request: @p0_tasks.cancel(model), gate: @host.Always, })
      } else {
        if reference == @semantics.snapshot(model.editor)[0].reference {
          ignore(@scene.dispatch(model.scene, Activate))
        }
        None
      }
    },
    activate_unhandled: () => @scene.dispatch(model.scene, Activate),
    shortcut: (key, _control, _shift) => {
      match key {
        @core.Key::Named(@core.NamedKey::F5) =>
          Some({ request: @p0_tasks.movement(model), gate: @host.PointerIdle, })
        @core.Key::Named(@core.NamedKey::F6) =>
          Some({ request: @p0_tasks.cancel(model), gate: @host.Always, })
        @core.Key::Named(@core.NamedKey::F7) =>
          Some({
            request: @p0_tasks.user(model, model.query()),
            gate: @host.CommittedInput,
          })
        _ => None
      }
    },
    navigation_blocked: () => model.control_focused(),
    navigate_unhandled: (x, y) => {
      if model.control_focused() {
        false
      } else {
        @scene.dispatch(model.scene, Move(x, y))
      }
    },
    scroll_unhandled: (_, _, _) => false,
    pointer_unhandled: (x, y) => {
      ignore(
        @semantics.focus(
          model.editor,
          @semantics.snapshot(model.editor)[0].reference,
        ),
      )
      @scene.dispatch(model.scene, Click(x, y))
    },
    resize: (width, height) => @scene.resize(model.scene, width, height),
    stop: () => ignore(model.stop()),
    can_close: () => true,
    close_requested: () => (),
    close_ready: () => false,
    input_error: message => model.set_input_error(message),
    edited: _ => None,
    dispose: () => (),
  }
}
