///|
async test "editing a memo does not reset its selection or rewrite unrelated controls" {
  let app = create_collection(
    { load: () => Ok(Some("original")), save: _ => Ok(()), },
    () => (),
    _ => (),
  )
  initialize(app)
  let input = app.default_input.unwrap()
  let row = (app.view)()[7].element.reference.unwrap()
  let action = (app.view)()[4].element.reference.unwrap()
  assert_eq(@semantics.set_text(app.editor, input, "original edited"), "")
  assert_eq(@semantics.set_selection(app.editor, input, 2, 5), "")
  let revision = @semantics.revision(app.editor)
  let request = (app.edited)({
    target: input,
    text: "original edited",
    revision,
  })
  assert_true(request is Some(_))
  assert_eq(@semantics.revision(app.editor), revision)
  ignore((app.activate)(row))
  let unchanged = @semantics.node(app.editor, input).unwrap()
  assert_eq(unchanged.value, "original edited")
  assert_eq((unchanged.selection_start, unchanged.selection_end), (2, 5))
  assert_eq((app.view)()[4].element.reference, Some(action))
  ignore((app.activate)(action))
  let pending_delete = @semantics.node(app.editor, input).unwrap()
  assert_eq(pending_delete.value, "original edited")
  assert_eq(
    (pending_delete.selection_start, pending_delete.selection_end),
    (2, 5),
  )
  assert_eq((app.view)()[4].element.text, "Confirm delete")
  (app.close_requested)()
  assert_eq((app.view)()[4].element.text, "Confirm delete")
  assert_false(@semantics.node(app.editor, action).unwrap().enabled)
  (app.stop)()
}
