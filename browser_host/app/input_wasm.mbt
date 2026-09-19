///|
fn input_document() -> @input_dom.Document = "websys" "input_document"

///|
fn input_window() -> @input_dom.Window = "websys" "input_window"

///|
fn InputElement::target(self : InputElement) -> @input_dom.EventTarget {
  match self {
    Editor(v) => v.as_event_target()
    Query(v) => v.as_event_target()
  }
}

///|
fn InputElement::value(self : InputElement) -> String {
  match self {
    Editor(v) => v.value()
    Query(v) => v.value()
  }
}

///|
fn InputElement::selection(self : InputElement) -> (Int, Int, Bool)? {
  match self {
    Editor(v) =>
      Some(
        (
          v.selection_start().reinterpret_as_int(),
          v.selection_end().reinterpret_as_int(),
          v.selection_direction() == "backward",
        ),
      )
    Query(v) => {
      guard v.selection_start() is Some(start) else { return None }
      guard v.selection_end() is Some(end) else { return None }
      Some(
        (
          start.reinterpret_as_int(),
          end.reinterpret_as_int(),
          v.selection_direction() == Some("backward"),
        ),
      )
    }
  }
}

///|
fn InputElement::active(self : InputElement) -> Bool {
  guard input_document().active_element() is Some(active) else { return false }
  active.is_same_node(
    Some(
      match self {
        Editor(v) => v.as_node()
        Query(v) => v.as_node()
      },
    ),
  )
}

///|
fn input_scroll(value : @input_dom.HTMLInputElement) -> Int {
  value.scroll_left().to_int()
}

///|
fn editor_scroll(value : @input_dom.HTMLTextAreaElement) -> Int {
  value.scroll_top().to_int()
}

///|
fn input_document_target() -> @input_dom.EventTarget {
  input_document().as_event_target()
}

///|
fn input_notify() -> Unit {
  ignore(
    input_document_target().dispatch_event(
      @input_dom.Event::new("metonic-input", {
        bubbles: None,
        cancelable: None,
        composed: None,
      }),
    ),
  )
}

///|
fn input_editor() -> @input_dom.HTMLTextAreaElement? {
  guard input_document().get_element_by_id("text-input") is Some(v) else {
    return None
  }
  @input_dom.HTMLTextAreaElement::from_element_opt(v)
}

///|
fn input_query() -> @input_dom.HTMLInputElement? {
  guard input_document().get_element_by_id("rpc-user") is Some(v) else {
    return None
  }
  @input_dom.HTMLInputElement::from_element_opt(v)
}

///|
fn input_event_composing(event : @input_dom.Event) -> Bool {
  match @input_dom.InputEvent::from_event_opt(event) {
    Some(v) => v.is_composing()
    None => false
  }
}

///|
fn input_event_data(event : @input_dom.Event) -> String? {
  @input_dom.CompositionEvent::from_event_opt(event).map(v => v.data())
}

///|
fn input_add_listener(
  target : @input_dom.EventTarget,
  name : String,
  callback : (@input_dom.Event) -> Unit,
) -> @input_dom.EventListener {
  let listener = @input_dom.EventListener::new(callback)
  target.add_event_listener(name, listener, false)
  listener
}

///|
fn input_remove_listener(
  target : @input_dom.EventTarget,
  name : String,
  listener : @input_dom.EventListener,
) -> Unit {
  target.remove_event_listener(name, listener, false)
}

///|
fn input_request_frame(callback : (Double) -> Unit) -> UInt {
  input_window().request_animation_frame(
    @input_dom.FrameRequestCallback::new(callback),
  )
}

///|
fn input_cancel_frame(frame : UInt) -> Unit {
  input_window().cancel_animation_frame(frame)
}
