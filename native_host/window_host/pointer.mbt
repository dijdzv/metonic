///|
fn App::apply_pointer(
  app : App,
  x : Int,
  y : Int,
  extend_selection : Bool,
) -> Unit raise {
  let view = (app.host.view)()
  for index = view.items.length() - 1; index >= 0; index = index - 1 {
    let item = view.items[index]
    if !item.element.bounds.contains(x, y) {
      continue
    }
    guard item.element.reference is Some(reference) else { continue }
    let node = match @semantics.node(app.host.editor, reference) {
      Ok(node) => node
      Err(_) => continue
    }
    if !node.enabled {
      continue
    }
    if node.role == @semantics.TextInput {
      ignore(@semantics.focus(app.host.editor, reference))
      if app.presenter is Some(presenter) {
        if presenter.hit_input(reference, x, y) is Some((offset, after)) {
          let caret = offset.min(node.value.length())
          ignore(
            @semantics.set_selection_directed(
              app.host.editor,
              reference,
              if extend_selection {
                node.selection_anchor
              } else {
                caret
              },
              caret,
            ),
          )
          if presenter.input_width(reference) is Some(width) {
            ignore(
              app.input_navigation.remember(
                reference,
                caret,
                width,
                after,
                None,
              ),
            )
          }
        }
      }
    } else {
      ignore(@semantics.focus(app.host.editor, reference))
      if (app.host.activate)(reference) is Some(action) {
        app.queue(ApplicationTask(action.request, action.gate))
      }
    }
    app.draw()
    return
  }
  ignore((app.host.pointer_unhandled)(x, y))
  app.draw()
}
