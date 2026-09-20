///|
fn main raise {
  let document = @dom.window().unwrap().get_document()
  let root = document.get_element_by_id("app").unwrap().to_node()
  let editor = @dom.HTMLTextAreaElement::from_js_value_opt(
    document.create_element("textarea").unwrap().to_js_value(),
  ).unwrap()
  let query = @dom.HTMLInputElement::from_js_value_opt(
    document.create_element("input").unwrap().to_js_value(),
  ).unwrap()
  editor.to_element().set_id("text-input")
  query.to_element().set_id("rpc-user")
  ignore(root.append_child(editor.to_node()).unwrap())
  ignore(root.append_child(query.to_node()).unwrap())
  @trace.start(field => {
    if field == "text-input" {
      Some("shared-state")
    } else {
      None
    }
  })
  for _ in 0..<300 {
    ignore(
      editor.to_event_target().dispatch_event(@dom.Event::new("input")).unwrap(),
    )
  }
  let first = @trace.snapshot()
  assert_true(first.contains("\"total\":300"))
  assert_true(first.contains("\"sequence\":45,"))
  assert_false(first.contains("\"sequence\":44,"))
  @trace.stop()
  ignore(
    query.to_event_target().dispatch_event(@dom.Event::new("input")).unwrap(),
  )
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
    query
    .to_event_target()
    .dispatch_event(
      @dom.CompositionEvent::new_with_event_init_dict("compositionupdate", {
        data: Some("あ"),
      }).to_event(),
    )
    .unwrap(),
  )
  let last = @trace.snapshot()
  assert_true(last.contains("\"total\":1"))
  assert_true(last.contains("\"field\":\"rpc-user\""))
  assert_true(last.contains("\"data\":\"あ\""))
  assert_true(last.contains("\"shared\":null"))
  assert_false(last.contains("new-state"))
  ignore(
    editor.to_event_target().dispatch_event(@dom.Event::new("input")).unwrap(),
  )
  assert_true(@trace.snapshot().contains("new-state"))
  let events = @trace.snapshot()
  editor.set_value("\n")
  editor.set_selection_range(1, 1)
  query.set_value("")
  ignore(query.set_selection_range(0, 0).unwrap())
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
    Some("PASS input_diagnostics capacity stop restart composition"),
  )
}
