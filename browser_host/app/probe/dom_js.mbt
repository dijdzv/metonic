///|
fn document() -> @dom.Document {
  @dom.window().unwrap().get_document()
}

///|
fn create_fields() -> (@dom.HTMLTextAreaElement, @dom.HTMLInputElement) {
  let root = document().get_element_by_id("app").unwrap().to_node()
  let editor = @dom.HTMLTextAreaElement::from_js_value_opt(
    document().create_element("textarea").unwrap().to_js_value(),
  ).unwrap()
  let query = @dom.HTMLInputElement::from_js_value_opt(
    document().create_element("input").unwrap().to_js_value(),
  ).unwrap()
  editor.to_element().set_id("text-input")
  query.to_element().set_id("rpc-user")
  ignore(root.append_child(editor.to_node()).unwrap())
  ignore(root.append_child(query.to_node()).unwrap())
  (editor, query)
}

///|
fn status(text : String) -> Unit {
  document()
  .get_element_by_id("app")
  .unwrap()
  .to_node()
  .set_text_content(Some(text))
}

///|
fn editor_target(value : @dom.HTMLTextAreaElement) -> @dom.EventTarget {
  value.to_event_target()
}

///|
fn query_target(value : @dom.HTMLInputElement) -> @dom.EventTarget {
  value.to_event_target()
}

///|
fn document_target() -> @dom.EventTarget {
  document().to_event_target()
}

///|
fn focus_editor(value : @dom.HTMLTextAreaElement) -> Unit {
  value.to_html_element().focus()
}

///|
fn focus_query(value : @dom.HTMLInputElement) -> Unit {
  value.to_html_element().focus()
}

///|
fn select_editor(
  value : @dom.HTMLTextAreaElement,
  start : UInt,
  end : UInt,
) -> Unit {
  value.set_selection_range(
    start.reinterpret_as_int(),
    end.reinterpret_as_int(),
  )
}

///|
fn select_query(
  value : @dom.HTMLInputElement,
  start : UInt,
  end : UInt,
) -> Unit {
  ignore(
    value
    .set_selection_range(start.reinterpret_as_int(), end.reinterpret_as_int())
    .unwrap(),
  )
}

///|
fn event(kind : String) -> @dom.Event {
  @dom.Event::new(kind)
}

///|
fn composition_event(kind : String, data? : String = "") -> @dom.Event {
  @dom.CompositionEvent::new_with_event_init_dict(kind, { data: Some(data), }).to_event()
}

///|
fn dispatch_event(target : @dom.EventTarget, value : @dom.Event) -> Unit {
  ignore(target.dispatch_event(value).unwrap())
}

///|
fn request_frame(callback : (Double) -> Unit) -> Unit {
  ignore(
    @dom.window()
    .unwrap()
    .request_animation_frame(@dom.FrameRequestCallback::from_fn(callback)),
  )
}
