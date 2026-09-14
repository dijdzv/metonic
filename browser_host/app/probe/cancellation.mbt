///|
fn check_canceled_replacement(
  editor : @dom.HTMLTextAreaElement,
  query : @dom.HTMLInputElement,
) -> Unit raise {
  for is_query in [false, true] {
    for canceled in ["あいう", ""] {
      @host.inputs_stop()
      editor.set_value("あいう")
      query.set_value("あいう")
      @host.inputs_start()
      let target = if is_query { (query : &@dom.TEventTarget) } else { (editor : &@dom.TEventTarget) }
      if is_query {
        query.focus()
        query.set_selection_range(0U, 3U)
      } else {
        editor.focus()
        editor.set_selection_range(0U, 3U)
      }
      ignore(target.dispatch_event(@dom.Event::new("select")))
      ignore(target.dispatch_event(@dom.CompositionEvent::new("compositionstart")))
      ignore(target.dispatch_event(@dom.CompositionEvent::new(
        "compositionupdate",
        event_init_dict=@dom.CompositionEventInit::new(data="あ"),
      )))
      if is_query {
        query.set_value("あ")
        query.set_selection_range(1U, 1U)
      } else {
        editor.set_value("あ")
        editor.set_selection_range(1U, 1U)
      }
      ignore(target.dispatch_event(@dom.Event::new("input")))
      assert_eq(@host.inputs_composing(), 1)
      if is_query {
        query.set_value(canceled)
        query.set_selection_range(0U, canceled.length().reinterpret_as_uint())
      } else {
        editor.set_value(canceled)
        editor.set_selection_range(0U, canceled.length().reinterpret_as_uint())
      }
      ignore(target.dispatch_event(@dom.CompositionEvent::new("compositionend")))
      assert_eq(@host.inputs_composing(), 0)
      assert_eq(@host.inputs_error(), 0)
      assert_eq(@app.view_field(if is_query { 6 } else { 0 }, 4), canceled.length())
      if !is_query {
        for index in 0..<canceled.length() {
          assert_eq(@app.editor_unit(index), canceled[index].to_int())
        }
        assert_eq(@app.editor_field(1), 0)
        assert_eq(@app.editor_field(2), canceled.length())
      }
      if is_query {
        query.set_value("次")
        query.set_selection_range(1U, 1U)
      } else {
        editor.set_value("次")
        editor.set_selection_range(1U, 1U)
      }
      ignore(target.dispatch_event(@dom.Event::new("input")))
      assert_eq(@app.view_field(if is_query { 6 } else { 0 }, 4), 1)
      if !is_query {
        assert_eq(@app.editor_unit(0), 0x6B21)
        assert_eq(@app.editor_field(1), 1)
        assert_eq(@app.editor_field(2), 1)
      }
      assert_eq(@host.inputs_error(), 0)
    }
  }
  @host.inputs_stop()
}
