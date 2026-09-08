///|
test "editing survives request replacement, failure recovery and resize" {
  let app = create(1, 1)
  let input = @semantics.snapshot(app.editor)[1].reference
  assert_eq(@semantics.set_text(app.editor, input, "日本 ABC"), "")
  assert_eq(@semantics.set_selection(app.editor, input, 3, 6), "")
  let obsolete = app.begin_update()
  let current = app.begin_update()
  assert_eq(app.complete_user(current, Err("domain:not_found")), true)
  assert_eq(app.result, "\nRPC: domain:not_found")
  assert_eq(app.complete_user(obsolete, Ok("obsolete")), false)
  let retry = app.begin_update()
  assert_eq(app.complete_user(retry, Ok("月兎")), true)
  assert_eq(@utf8.decode(app.result_utf8), "\n月兎")
  assert_eq(@semantics.replace_selection(app.editor, input, "XYZ"), "")
  assert_eq(@scene.resize(app.scene, 480, 300), true)
  let movement = app.begin_update()
  assert_eq(app.complete_movement(movement, 100), true)
  assert_eq(@scene.field(app.scene, 0), 100)
  assert_eq(@scene.field(app.scene, 6), 480)
  assert_eq(@semantics.snapshot(app.editor)[1].value, "日本 XYZ")
  assert_eq(app.result, "\n月兎")
}

///|
test "cancel and shutdown preserve the last application snapshot" {
  let app = create(1, 1)
  let initial = app.begin_update()
  assert_eq(app.complete_user(initial, Ok("retained")), true)
  let canceled = app.begin_update()
  assert_eq(app.cancel_update(), true)
  assert_eq(app.complete_user(canceled, Err("late failure")), false)
  let pending = app.begin_update()
  let x = @scene.field(app.scene, 0)
  let node_count = @semantics.snapshot(app.editor).length()
  assert_eq(app.stop(), true)
  assert_eq(app.complete_movement(pending, 0), false)
  assert_eq(app.complete_user(pending, Ok("late success")), false)
  assert_eq(app.begin_update(), -1)
  assert_eq(@scene.field(app.scene, 0), x)
  assert_eq(app.result, "\nretained")
  assert_eq(@utf8.decode(app.result_utf8), app.result)
  assert_eq(@semantics.snapshot(app.editor).length(), node_count)
}

///|
test "separate host instances do not share an editing session" {
  let native = create(1, 1)
  let browser = create(1, 1)
  assert_eq(
    @semantics.set_text(
      native.editor,
      @semantics.snapshot(native.editor)[1].reference,
      "native",
    ),
    "",
  )
  assert_eq(native.complete_user(native.begin_update(), Ok("one")), true)
  assert_eq(@semantics.snapshot(browser.editor)[1].value, "")
  assert_eq(browser.result, "")
  assert_eq(@task_scope.field(browser.tasks, 0), 0)
}
