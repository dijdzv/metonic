///|
fn App::accessibility_target(app : App, id : Int) -> @semantics.Node? {
  for node in @semantics.snapshot(app.host.editor) {
    if node.reference.id == id && node.enabled {
      return Some(node)
    }
  }
  None
}

///|
fn App::apply_accessibility(
  app : App,
  request : @accessibility.Request,
) -> Unit raise {
  match request {
    @accessibility.Focus(target) => {
      guard app.accessibility_target(target) is Some(node) else { return }
      if app.window is Some(window) {
        window.focus_window()
      }
      ignore(@semantics.focus(app.host.editor, node.reference))
    }
    @accessibility.Click(target) => {
      guard app.accessibility_target(target) is Some(node) else { return }
      guard node.role == @semantics.Button else { return }
      ignore(@semantics.focus(app.host.editor, node.reference))
      if (app.host.activate)(node.reference) is Some(action) {
        app.queue(ApplicationTask(action.request, action.gate, () => ()))
      } else {
        ignore(app.publish())
      }
    }
    @accessibility.SetValue(target, text) => {
      guard app.accessibility_target(target) is Some(node) else { return }
      guard node.role == @semantics.TextInput && !node.read_only else { return }
      ignore(@semantics.set_text(app.host.editor, node.reference, text))
      app.report_edit(node.reference, node.value)
    }
    @accessibility.Select(_, _, _, _) => {
      guard app.accessibility is Some(bridge) else { return }
      guard bridge.resolve_selection(request) is Some((anchor, caret)) else {
        return
      }
      guard (app.host.view)().accessibility.text_owner is Some(reference) else {
        return
      }
      ignore(@semantics.focus(app.host.editor, reference))
      ignore(
        @semantics.set_selection_directed(
          app.host.editor,
          reference,
          anchor,
          caret,
        ),
      )
    }
  }
  app.draw()
}
