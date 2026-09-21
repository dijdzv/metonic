///|
test "input failures appear in the view without replacing the note" {
  let model = create()
  let app = model.application()
  let original = @semantics.node(model.editor, model.note).unwrap().value
  (app.input_error)(Some("Clipboard: unavailable"))
  let view = (app.view)()
  assert_eq(view.length(), 3)
  assert_true(view[2].kind is @app.Text)
  assert_eq(view[2].element.text, "Clipboard: unavailable")
  assert_eq(@semantics.node(model.editor, model.note).unwrap().value, original)
  (app.input_error)(None)
  assert_eq((app.view)().length(), 2)
}
