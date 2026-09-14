///|
fn App::navigate_vertical(
  app : App,
  down : Bool,
  extend_selection : Bool,
) -> Unit raise {
  let node = app.input_node()
  if !node.focused {
    ignore(@scene.dispatch(app.model.scene, Move(0, if down { 10 } else { -10 })))
    app.draw()
    return
  }
  if node.reference == app.model.query_input {
    return
  }
  guard app.raster is Some(engine) else { return }
  let caret = @semantics.caret(node)
  let revision = @semantics.revision(app.model.editor)
  let preferred = match app.vertical_goal {
    Some((old_revision, old_caret, width, x)) if old_revision == revision && old_caret == caret && width == app.text_width => x
    _ => None
  }
  guard @raster.vertical_position(engine, node.value, caret, down, preferred)
    is Some((target, x)) else { return }
  require(
    @semantics.set_selection_directed(
      app.model.editor,
      node.reference,
      if extend_selection { node.selection_anchor } else { target },
      target,
    ) == "",
    "vertical caret selection rejected",
  )
  app.vertical_goal = Some((@semantics.revision(app.model.editor), target, app.text_width, x))
  app.draw()
}
