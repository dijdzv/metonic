///|
fn App::edit_clipboard(
  app : App,
  action : @text_clipboard.Action,
) -> Unit raise {
  if app.composition is Some(_) || app.ime_pointer.pending() {
    return
  }
  guard app.input_node() is Some(node) else { return }
  if !node.focused || !node.enabled {
    return
  }
  let inputs = (app.host.view)().inputs
  guard inputs.iter().find_first(input => input.reference == node.reference)
    is Some(input) else {
    return
  }
  app.cancel_pointer()
  match
    @text_clipboard.apply(
      app.host.editor,
      node.reference,
      action,
      app.clipboard,
      single_line=input.single_line,
    ) {
    Ok(_) => {
      app.report_edit(node.reference, node.value)
      (app.host.input_error)(None)
    }
    Err(error) => (app.host.input_error)(Some("Clipboard: " + error))
  }
  app.input_navigation.reset()
  app.draw()
}
