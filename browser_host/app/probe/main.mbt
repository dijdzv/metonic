///|
fn main raise {
  let (editor, query) = create_fields()
  check_resize_scroll(editor)
  editor.set_value("A😀日本")
  query.set_value("1")
  @host.initialize()
  @host.inputs_start()
  assert_eq(@host.inputs_error(), 0)
  assert_eq(@app.editor_field(0), 5)
  focus_editor(editor)
  select_editor(editor, 1U, 3U)
  ignore(dispatch_event(document_target(), event("selectionchange")))
  assert_eq(@app.editor_field(1), 1)
  assert_eq(@app.editor_field(2), 3)
  ignore(
    dispatch_event(editor_target(editor), composition_event("compositionstart")),
  )
  assert_eq(@host.inputs_composing(), 1)
  ignore(
    dispatch_event(
      editor_target(editor),
      composition_event("compositionupdate", data="にほん"),
    ),
  )
  editor.set_value("Aにほん日本")
  select_editor(editor, 2U, 2U)
  ignore(dispatch_event(editor_target(editor), event("input")))
  assert_eq(@app.editor_field(0), 5)
  editor.set_value("A日本日本")
  select_editor(editor, 3U, 3U)
  ignore(
    dispatch_event(editor_target(editor), composition_event("compositionend")),
  )
  assert_eq(@host.inputs_composing(), 0)
  assert_eq(@app.editor_unit(1), 0x65E5)
  focus_query(query)
  ignore(
    dispatch_event(query_target(query), composition_event("compositionstart")),
  )
  assert_eq(@host.inputs_composing(), 1)
  ignore(
    dispatch_event(
      query_target(query),
      composition_event("compositionupdate", data="に"),
    ),
  )
  query.set_value("2")
  select_query(query, 1U, 1U)
  ignore(
    dispatch_event(query_target(query), composition_event("compositionend")),
  )
  assert_eq(@host.inputs_error(), 0)
  assert_eq(@host.inputs_composing(), 0)
  let revision = @app.editor_field(3)
  @host.inputs_stop()
  @host.inputs_stop()
  editor.set_value("late")
  ignore(dispatch_event(editor_target(editor), event("input")))
  ignore(
    dispatch_event(query_target(query), composition_event("compositionstart")),
  )
  ignore(dispatch_event(document_target(), event("selectionchange")))
  assert_eq(@app.editor_field(3), revision)
  assert_eq(@host.inputs_composing(), 0)
  @host.inputs_start()
  assert_eq(@app.editor_field(0), 4)
  assert_eq(@host.inputs_error(), 0)
  @host.inputs_stop()
  check_canceled_replacement(editor, query)
  check_frame_lifetime(editor, query, 0)
}
