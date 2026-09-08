///|
test "editor preserves committed state on invalid selection and rejects late input after stop" {
  reset_state()
  assert_true(accept_editor("A😀日本語B", 1, 3))
  let revision = editor_field(3)
  assert_false(accept_editor("changed", 0, 100))
  assert_eq(editor_field(3), revision)
  assert_eq(
    @semantics.snapshot(application.val.editor)[1].value,
    "A😀日本語B",
  )
  assert_false(accept_editor("A😀B", 2, 3))
  assert_eq(editor_field(3), revision)
  editor_dispose()
  assert_false(accept_editor("late", 4, 4))
  assert_eq(editor_field(0), -1)
  reset_state()
  assert_eq(editor_field(0), 0)
  assert_true(accept_editor("再開", 2, 2))
}

///|
test "composition previews selected text without committing and reset rejects late updates" {
  reset_state()
  assert_true(accept_editor("A😀B", 1, 3))
  let revision = editor_field(3)
  assert_eq(editor_composition_start(), 1)
  assert_eq(text_begin(2), 1)
  assert_eq(text_put(0x65E5), 1)
  assert_eq(text_put(0x672C), 1)
  assert_eq(editor_composition_update(), 1)
  assert_eq(editor_display(), "A日本B")
  assert_eq(@semantics.snapshot(application.val.editor)[1].value, "A😀B")
  assert_eq(editor_field(3), revision)
  assert_false(accept_editor("premature", 0, 0))
  editor_composition_end()
  assert_eq(editor_display(), "A😀B")
  assert_true(accept_editor("A日本B", 3, 3))
  assert_eq(editor_composition_start(), 1)
  reset_state()
  assert_eq(text_begin(1), 1)
  assert_eq(text_put(65), 1)
  assert_eq(editor_composition_update(), 0)
  assert_eq(editor_display(), "")
}
