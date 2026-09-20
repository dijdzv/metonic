///|
fn App::editor_caret_after(app : App, caret : Int, width : Int) -> Bool {
  app.input_navigation.after(
    app.model.editor_input,
    caret,
    width,
    app.composition is Some(_),
  )
}

///|
fn App::navigate_vertical(
  app : App,
  down : Bool,
  extend_selection : Bool,
) -> Unit raise {
  let node = app.input_node()
  if !node.focused {
    ignore(
      @scene.dispatch(app.model.scene, Move(0, if down { 10 } else { -10 })),
    )
    app.draw()
    return
  }
  if app.input_layouts.single_line(node.reference) != Some(false) {
    return
  }
  guard app.input_layouts.engine(node.reference) is Some(engine) else { return }
  let caret = @semantics.caret(node)
  let preferred = app.input_navigation.preferred_x(
    node.reference,
    caret,
    app.text_width,
  )
  guard @raster.vertical_caret(
      engine,
      node.value,
      caret,
      down,
      preferred,
      after=app.editor_caret_after(caret, app.text_width),
    )
    is Some((target, after, x)) else {
    return
  }
  require(
    @semantics.set_selection_directed(
      app.model.editor,
      node.reference,
      if extend_selection {
        node.selection_anchor
      } else {
        target
      },
      target,
    ) ==
    "",
    "vertical caret selection rejected",
  )
  ignore(
    app.input_navigation.remember(
      node.reference,
      target,
      app.text_width,
      after,
      x,
    ),
  )
  app.draw()
}
