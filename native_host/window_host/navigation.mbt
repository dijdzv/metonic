///|
fn App::navigate_vertical(
  app : App,
  down : Bool,
  extend_selection : Bool,
) -> Unit raise {
  guard app.input_node() is Some(node) && node.focused else {
    if (app.host.navigate_unhandled)(0, if down { 10 } else { -10 }) {
      ignore(app.publish())
    }
    app.draw()
    return
  }
  if app.input_layouts.single_line(node.reference) != Some(false) {
    return
  }
  guard app.input_layouts.engine(node.reference) is Some(engine) else { return }
  guard app.presenter is Some(presenter) else { return }
  guard presenter.input_width(node.reference) is Some(width) else { return }
  let caret = @semantics.caret(node)
  let preferred = app.input_navigation.preferred_x(node.reference, caret, width)
  guard @raster.vertical_caret(
      engine,
      node.value,
      caret,
      down,
      preferred,
      after=app.input_navigation.after(
        node.reference,
        caret,
        width,
        app.composition is Some(_),
      ),
    )
    is Some((target, after, x)) else {
    return
  }
  require(
    @semantics.set_selection_directed(
      app.host.editor,
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
  ignore(app.input_navigation.remember(node.reference, target, width, after, x))
  app.draw()
}
