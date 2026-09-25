///|
test "native adapter keeps offscreen semantics without rendering their controls" {
  let tree = @semantics.empty(1, 1)
  let visible = @semantics.add_button(tree, "Visible").unwrap()
  let offscreen = @semantics.add_button(tree, "Offscreen").unwrap()
  let bounds : @view.Bounds = { x: 10, y: 20, width: 80, height: 24, }
  let app : @portable.Application = {
    title: "Test",
    editor: tree,
    default_input: None,
    initial_size: (120, 80),
    viewport: None,
    publications: None,
    downstreams: None,
    serials: None,
    components: None,
    connect_tasks: _ => (),
    initialize: () => None,
    view: () => {
      [
        {
          element: {
            bounds,
            text: "Visible",
            reference: Some(visible),
            focused: false,
          },
          kind: @portable.Button,
          clip: None,
        },
      ]
    },
    activate: _ => None,
    edited: _ => None,
    resize: (_, _) => false,
    stop: () => (),
    can_close: () => true,
    close_requested: () => (),
    close_ready: () => true,
    input_error: _ => (),
    dispose: () => (),
  }
  let view = (from_application(app).view)()
  assert_eq(view.items.length(), 1)
  assert_eq(view.accessibility.controls.length(), 2)
  let visible_control = view.accessibility.controls
    .iter()
    .find_first(control => control.reference == visible)
    .unwrap()
  assert_eq(visible_control.bounds, bounds)
  let offscreen_control = view.accessibility.controls
    .iter()
    .find_first(control => control.reference == offscreen)
    .unwrap()
  assert_eq(offscreen_control.bounds, { x: 0, y: 0, width: 0, height: 0, })
  ignore(@semantics.dispose(tree))
}

///|
test "native adapter exposes host-boundary controlled input synchronization" {
  let scope = @reactive.Scope::root(@reactive.Graph::new())
  let tree = @semantics.empty(2, 1)
  let ui = @component.UiRoot::new(scope, tree)
  let value = @reactive.Signal::new(scope, "initial")
  let input = ui.fixed("form").text_input(
    "name", "Name",
    @component.Controlled::new(() => value.peek(), text => {
      value.set(text)
      None
    }),
  ).unwrap()
  let app : @portable.Application = {
    title: "Controlled",
    editor: tree,
    default_input: Some(input),
    initial_size: (120, 80),
    viewport: None,
    publications: None,
    downstreams: None,
    serials: None,
    components: Some(ui),
    connect_tasks: _ => (),
    initialize: () => None,
    view: () => [],
    activate: _ => None,
    edited: edit => ui.edited(edit.target, edit.text, edit.revision),
    resize: (_, _) => false,
    stop: () => (),
    can_close: () => true,
    close_requested: () => (),
    close_ready: () => true,
    input_error: _ => (),
    dispose: () => scope.dispose(),
  }
  let host = from_application(app)
  value.set("updated")
  assert_true((host.synchronize_controls)(Some(input)) == false)
  assert_eq(@semantics.node(tree, input).unwrap().value, "initial")
  assert_true((host.synchronize_controls)(None))
  assert_eq(@semantics.node(tree, input).unwrap().value, "updated")
  scope.dispose()
  ignore(@semantics.dispose(tree))
}
