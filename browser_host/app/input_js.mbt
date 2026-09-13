///|
extern "js" fn input_document() -> @input_dom.Document =
  #| () => document

///|
extern "js" fn input_window() -> @input_dom.Window =
  #| () => window

///|
fn InputElement::target(self : InputElement) -> @input_dom.EventTarget {
  match self {
    Editor(v) => v.to_event_target()
    Query(v) => v.to_event_target()
  }
}

///|
fn InputElement::value(self : InputElement) -> String {
  match self {
    Editor(v) => v.get_value()
    Query(v) => v.get_value()
  }
}

///|
fn InputElement::selection(self : InputElement) -> (Int, Int, Bool)? {
  match self {
    Editor(v) =>
      Some(
        (
          v.get_selection_start(),
          v.get_selection_end(),
          v.get_selection_direction() == "backward",
        ),
      )
    Query(v) => {
      guard v.get_selection_start() is Some(start) else { return None }
      guard v.get_selection_end() is Some(end) else { return None }
      Some((start, end, v.get_selection_direction() == Some("backward")))
    }
  }
}

///|
fn InputElement::active(self : InputElement) -> Bool {
  guard input_document().get_active_element() is Some(active) else {
    return false
  }
  active
  .to_node()
  .is_same_node(
    Some(
      match self {
        Editor(v) => v.to_node()
        Query(v) => v.to_node()
      },
    ),
  )
}

///|
fn input_scroll(value : @input_dom.HTMLInputElement) -> Int {
  value.to_element().get_scroll_left().to_int()
}

///|
fn input_document_target() -> @input_dom.EventTarget {
  input_document().to_event_target()
}

///|
fn input_notify() -> Unit {
  ignore(
    input_document_target().dispatch_event(
      @input_dom.Event::new("metonic-input"),
    ),
  )
}

///|
fn input_editor() -> @input_dom.HTMLTextAreaElement? {
  guard input_document().get_element_by_id("text-input") is Some(v) else {
    return None
  }
  @input_dom.HTMLTextAreaElement::from_js_value_opt(v.to_js_value())
}

///|
fn input_query() -> @input_dom.HTMLInputElement? {
  guard input_document().get_element_by_id("rpc-user") is Some(v) else {
    return None
  }
  @input_dom.HTMLInputElement::from_js_value_opt(v.to_js_value())
}

///|
fn input_event_composing(event : @input_dom.Event) -> Bool {
  match @input_dom.InputEvent::from_js_value_opt(event.to_js_value()) {
    Some(v) => v.get_is_composing()
    None => false
  }
}

///|
fn input_event_data(event : @input_dom.Event) -> String? {
  @input_dom.CompositionEvent::from_js_value_opt(event.to_js_value()).map(v => {
    v.get_data()
  })
}

///|
fn input_add_listener(
  target : @input_dom.EventTarget,
  name : String,
  callback : (@input_dom.Event) -> Unit,
) -> @input_dom.EventListener {
  let listener = @input_dom.EventListener::from_fn(callback)
  target.add_event_listener(name, Some(listener))
  listener
}

///|
fn input_remove_listener(
  target : @input_dom.EventTarget,
  name : String,
  listener : @input_dom.EventListener,
) -> Unit {
  target.remove_event_listener(name, Some(listener))
}

///|
fn input_request_frame(callback : (Double) -> Unit) -> UInt {
  input_window()
  .request_animation_frame(@input_dom.FrameRequestCallback::from_fn(callback))
  .reinterpret_as_uint()
}

///|
fn input_cancel_frame(frame : UInt) -> Unit {
  input_window().cancel_animation_frame(frame.reinterpret_as_int())
}
