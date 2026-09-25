///|
fn App::activate_focused(app : App) -> Unit raise {
  for node in @semantics.snapshot(app.host.editor) {
    if !node.focused {
      continue
    }
    if node.enabled && node.role == @semantics.Button {
      if (app.host.activate)(node.reference) is Some(action) {
        app.queue(ApplicationTask(action.request, action.gate, () => ()))
      } else {
        ignore(app.publish())
      }
      app.draw()
    }
    return
  }
  if (app.host.activate_unhandled)() {
    ignore(app.publish())
    app.draw()
  }
}
