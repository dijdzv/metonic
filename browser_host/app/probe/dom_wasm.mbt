///|
fn document() -> @dom.Document = "websys" "input_document"

///|
fn window() -> @dom.Window = "websys" "input_window"

///|
fn create_fields() -> (@dom.HTMLTextAreaElement, @dom.HTMLInputElement) {
  let root = document().get_element_by_id("app").unwrap()
  let editor = @dom.HTMLTextAreaElement::from_element_opt(
    document().create_element("textarea"),
  ).unwrap()
  let query = @dom.HTMLInputElement::from_element_opt(
    document().create_element("input"),
  ).unwrap()
  editor.set_id("text-input")
  query.set_id("rpc-user")
  ignore(root.append_child(editor.as_node()))
  ignore(root.append_child(query.as_node()))
  (editor, query)
}

///|
fn status(text : String) -> Unit {
  document().get_element_by_id("app").unwrap().set_text_content(Some(text))
}

///|
fn editor_target(value : @dom.HTMLTextAreaElement) -> @dom.EventTarget {
  value.as_event_target()
}

///|
fn query_target(value : @dom.HTMLInputElement) -> @dom.EventTarget {
  value.as_event_target()
}

///|
fn document_target() -> @dom.EventTarget {
  document().as_event_target()
}

///|
fn focus_editor(value : @dom.HTMLTextAreaElement) -> Unit {
  value.focus()
}

///|
fn focus_query(value : @dom.HTMLInputElement) -> Unit {
  value.focus()
}

///|
fn select_editor(
  value : @dom.HTMLTextAreaElement,
  start : UInt,
  end : UInt,
) -> Unit {
  value.set_selection_range(start, end, "none")
}

///|
fn select_query(
  value : @dom.HTMLInputElement,
  start : UInt,
  end : UInt,
) -> Unit {
  value.set_selection_range(start, end, "none")
}

///|
fn event(kind : String) -> @dom.Event {
  @dom.Event::new(kind, { bubbles: None, cancelable: None, composed: None, })
}

///|
fn composition_event(kind : String, data? : String = "") -> @dom.Event {
  @dom.CompositionEvent::new(kind, {
    bubbles: None,
    cancelable: None,
    composed: None,
    data: Some(data),
  }).as_event()
}

///|
fn dispatch_event(target : @dom.EventTarget, value : @dom.Event) -> Unit {
  ignore(target.dispatch_event(value))
}

///|
fn request_frame(callback : (Double) -> Unit) -> Unit {
  ignore(
    window().request_animation_frame(@dom.FrameRequestCallback::new(callback)),
  )
}
