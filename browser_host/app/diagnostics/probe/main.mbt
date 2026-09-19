///|
fn main raise {
  let root = @dom.document().get_element_by_id("app")
  let editor : @dom.HTMLTextAreaElement = @dom.document()
    .create_element("textarea")
    .unsafe_into()
  let query : @dom.HTMLInputElement = @dom.document()
    .create_element("input")
    .unsafe_into()
  editor.set_id("text-input")
  query.set_id("rpc-user")
  ignore(root.append_child(editor))
  ignore(root.append_child(query))
  @trace.start(field => {
    if field == "text-input" {
      Some("shared-state")
    } else {
      None
    }
  })
  for _ in 0..<300 {
    ignore(editor.dispatch_event(@dom.Event::new("input")))
  }
  let first = @trace.snapshot()
  assert_true(first.contains("\"total\":300"))
  assert_true(first.contains("\"sequence\":45,"))
  assert_false(first.contains("\"sequence\":44,"))
  @trace.stop()
  ignore(query.dispatch_event(@dom.Event::new("input")))
  assert_eq(@trace.snapshot(), first)
  @trace.start(field => {
    if field == "text-input" {
      Some("new-state")
    } else {
      None
    }
  })
  query.set_value("あ")
  ignore(
    query.dispatch_event(
      @dom.CompositionEvent::new(
        "compositionupdate",
        event_init_dict=@dom.CompositionEventInit::new(data="あ"),
      ),
    ),
  )
  let last = @trace.snapshot()
  assert_true(last.contains("\"total\":1"))
  assert_true(last.contains("\"field\":\"rpc-user\""))
  assert_true(last.contains("\"data\":\"あ\""))
  assert_true(last.contains("\"shared\":null"))
  assert_false(last.contains("new-state"))
  ignore(editor.dispatch_event(@dom.Event::new("input")))
  assert_true(@trace.snapshot().contains("new-state"))
  let events = @trace.snapshot()
  editor.set_value("\n")
  editor.set_selection_range(1U, 1U)
  query.set_value("")
  query.set_selection_range(0U, 0U)
  let sample = @trace.sample()
  assert_true(sample.contains("\"value\":\"\\n\""))
  assert_true(sample.contains("\"value\":\"\""))
  assert_true(sample.contains("\"start\":1"))
  assert_true(sample.contains("\"start\":0"))
  assert_true(sample.contains("\"shared\":null"))
  assert_true(sample.contains("new-state"))
  assert_eq(@trace.snapshot(), events)
  @trace.stop()
  assert_true(@trace.sample().contains("\"fields\":[]"))
  root.set_text_content(
    "PASS input_diagnostics capacity stop restart composition",
  )
}
