///|
fn check_canceled_replacement(
  editor : @dom.HTMLTextAreaElement,
  query : @dom.HTMLInputElement,
) -> Unit raise {
  for is_query in [false, true] {
    for canceled in ["あいう", "", "かきく", "A😀B"] {
      @host.inputs_stop()
      editor.set_value("あいう")
      query.set_value("あいう")
      @host.inputs_start()
      let target = if is_query {
        query_target(query)
      } else {
        editor_target(editor)
      }
      if is_query {
        focus_query(query)
        select_query(query, 0U, 3U)
      } else {
        focus_editor(editor)
        select_editor(editor, 0U, 3U)
      }
      ignore(dispatch_event(target, event("select")))
      ignore(dispatch_event(target, composition_event("compositionstart")))
      ignore(
        dispatch_event(
          target,
          composition_event("compositionupdate", data="あ"),
        ),
      )
      if is_query {
        query.set_value("あ")
        select_query(query, 1U, 1U)
      } else {
        editor.set_value("あ")
        select_editor(editor, 1U, 1U)
      }
      ignore(dispatch_event(target, event("input")))
      assert_eq(@host.inputs_composing(), 1)
      if is_query {
        query.set_value(canceled)
        select_query(query, 0U, canceled.length().reinterpret_as_uint())
      } else {
        editor.set_value(canceled)
        select_editor(editor, 0U, canceled.length().reinterpret_as_uint())
      }
      ignore(dispatch_event(target, composition_event("compositionend")))
      assert_eq(@host.inputs_composing(), 0)
      assert_eq(@host.inputs_error(), 0)
      assert_eq(
        @app.view_field(if is_query { 6 } else { 0 }, 4),
        canceled.length(),
      )
      if is_query {
        assert_eq(@app.query_state(), (canceled, 0, canceled.length(), false))
      } else {
        for index in 0..<canceled.length() {
          assert_eq(@app.editor_unit(index), canceled[index].to_int())
        }
        assert_eq(@app.editor_field(1), 0)
        assert_eq(@app.editor_field(2), canceled.length())
      }
      if is_query {
        query.set_value("次")
        select_query(query, 1U, 1U)
      } else {
        editor.set_value("次")
        select_editor(editor, 1U, 1U)
      }
      ignore(dispatch_event(target, event("input")))
      assert_eq(@app.view_field(if is_query { 6 } else { 0 }, 4), 1)
      if is_query {
        assert_eq(@app.query_state(), ("次", 1, 1, false))
      } else {
        assert_eq(@app.editor_unit(0), 0x6B21)
        assert_eq(@app.editor_field(1), 1)
        assert_eq(@app.editor_field(2), 1)
      }
      assert_eq(@host.inputs_error(), 0)
    }
  }
  @host.inputs_stop()
}
