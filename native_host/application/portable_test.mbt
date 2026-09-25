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
