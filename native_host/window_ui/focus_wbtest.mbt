///|
fn focused_name(model : @application.Model) -> String {
  for node in @semantics.snapshot(model.editor) {
    if node.focused {
      return node.name
    }
  }
  ""
}

///|
test "Tab and Shift Tab traverse the complete demo in opposite directions" {
  let model = @application.create(1, 1)
  for
    name in [
      "Text", "Toggle", "Load user", "Move after delay", "Cancel", "User ID", "Text",
    ] {
    move_focus(model, false)
    assert_eq(focused_name(model), name)
  }
  for
    name in [
      "User ID", "Cancel", "Move after delay", "Load user", "Toggle", "Text",
    ] {
    move_focus(model, true)
    assert_eq(focused_name(model), name)
  }
}

///|
test "reverse entry and round trip preserve text and selection" {
  let model = @application.create(1, 1)
  assert_eq(
    @semantics.set_text(model.editor, model.query_input, "あいう"),
    "",
  )
  assert_eq(@semantics.set_selection(model.editor, model.query_input, 1, 3), "")
  move_focus(model, true)
  assert_eq(focused_name(model), "User ID")
  move_focus(model, true)
  move_focus(model, false)
  assert_eq(focused_name(model), "User ID")
  let query = @semantics.snapshot(model.editor)[5]
  assert_eq(query.value, "あいう")
  assert_eq(query.selection_start, 1)
  assert_eq(query.selection_end, 3)
}
