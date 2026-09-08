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

///|
test "task status follows cancellation and reuse without replacing editor contents" {
  let app = create(1, 1)
  let input = @semantics.snapshot(app.editor)[1].reference
  assert_eq(@semantics.set_text(app.editor, input, "日本 ABC"), "")
  assert_eq(app.view().task_status.text, "Idle")
  let canceled = app.begin_update()
  assert_eq(app.view().task_status.text, "Working...")
  assert_eq(app.cancel_update(), true)
  assert_eq(app.view().task_status.text, "Canceled")
  assert_eq(app.complete_movement(canceled, 40), false)
  assert_eq(app.view().task_status.text, "Canceled")
  let next = app.begin_update()
  assert_eq(app.complete_movement(next, 40), true)
  assert_eq(app.view().task_status.text, "Completed")
  let failed = app.begin_update()
  assert_eq(app.complete_user(failed, Err("Unavailable")), true)
  assert_eq(app.view().task_status.text, "Failed")
  assert_eq(app.view().editor.text, "日本 ABC")
  ignore(app.stop())
  assert_eq(app.view().task_status.text, "Stopped")
}
