///|
fn next_frame(check : () -> Unit raise) -> Unit {
  ignore(
    request_frame(fn(_) {
      check() catch {
        error => status("FAIL production_input_owner: " + error.to_string())
      }
    }),
  )
}

///|
fn check_frame_lifetime(
  editor : @dom.HTMLTextAreaElement,
  query : @dom.HTMLInputElement,
  scenario : Int,
) -> Unit raise {
  if scenario == 6 {
    @host.inputs_stop()
    status(
      "PASS production_input_owner both_fields composition selection stop restart pending_frames",
    )
    return
  }
  let is_query = scenario >= 3
  let mode = scenario % 3
  @host.inputs_stop()
  editor.set_value("editor")
  query.set_value("query")
  @host.inputs_start()
  if is_query {
    focus_query(query)
    select_query(query, 0U, 5U)
    ignore(
      dispatch_event(query_target(query), composition_event("compositionstart")),
    )
    ignore(
      dispatch_event(
        query_target(query),
        composition_event("compositionupdate", data="pending"),
      ),
    )
    query.set_value("pending")
    select_query(query, 7U, 7U)
  } else {
    focus_editor(editor)
    select_editor(editor, 0U, 6U)
    ignore(
      dispatch_event(
        editor_target(editor),
        composition_event("compositionstart"),
      ),
    )
    ignore(
      dispatch_event(
        editor_target(editor),
        composition_event("compositionupdate", data="pending"),
      ),
    )
    editor.set_value("pending")
    select_editor(editor, 7U, 7U)
  }
  assert_eq(@host.inputs_composing(), 1)
  assert_eq(@app.input_cursor(is_query, "pending", 7), 0)
  if mode != 0 {
    @host.inputs_stop()
  }
  if mode == 2 {
    editor.set_value("restarted-editor")
    query.set_value("restarted-query")
    @host.inputs_start()
  }
  let revision = @app.editor_field(3)
  let editor_length = @app.editor_field(0)
  let query_length = @app.view_field(6, 4)
  next_frame(fn() {
    next_frame(fn() raise {
      assert_eq(@host.inputs_error(), 0)
      assert_eq(@app.editor_field(3), revision)
      assert_eq(@app.editor_field(0), editor_length)
      assert_eq(@app.view_field(6, 4), query_length)
      if mode == 0 {
        assert_eq(@host.inputs_composing(), 1)
        assert_eq(@app.input_cursor(is_query, "pending", 7), 1)
      } else {
        assert_eq(@host.inputs_composing(), 0)
        assert_eq(@app.input_cursor(is_query, "pending", 7), 0)
      }
      check_frame_lifetime(editor, query, scenario + 1)
    })
  })
}
