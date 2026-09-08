///|
test "request focus preserves edited content and shares resized hit bounds" {
  let app = create(1, 1)
  let input = @semantics.snapshot(app.editor)[1].reference
  assert_eq(@semantics.set_text(app.editor, input, "日本 ABC"), "")
  assert_eq(@semantics.focus(app.editor, input), "")
  assert_eq(app.focus_request(), true)
  let view = app.view()
  assert_eq(view.editor.text, "日本 ABC")
  assert_eq(view.editor.focused, false)
  assert_eq(view.request.focused, true)
  assert_eq(view.request.text, "Load user")
  assert_eq(view.request.reference, Some(app.request_button))
  assert_eq(view.request.bounds.contains(20, 160), true)
  assert_eq(view.request.bounds.contains(20, 104), false)
  ignore(@scene.resize(app.scene, 120, 300))
  let narrow = app.view()
  assert_eq(narrow.request.bounds.width, 104)
  assert_eq(narrow.request.bounds.contains(112, 160), false)
  assert_eq(narrow.editor.text, "日本 ABC")
}
