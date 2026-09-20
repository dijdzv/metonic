///|
extern "js" fn input_document() -> @input_dom.Document =
  #| () => document

///|
extern "js" fn input_window() -> @input_dom.Window =
  #| () => window

///|
fn Element::target(self : Element) -> @input_dom.EventTarget {
  match self {
    Multiline(v) => v.to_event_target()
    SingleLine(v) => v.to_event_target()
  }
}

///|
pub fn Element::value(self : Element) -> String {
  match self {
    Multiline(v) => v.get_value()
    SingleLine(v) => v.get_value()
  }
}

///|
fn Element::selection(self : Element) -> (Int, Int, Bool)? {
  match self {
    Multiline(v) =>
      Some(
        (
          v.get_selection_start(),
          v.get_selection_end(),
          v.get_selection_direction() == "backward",
        ),
      )
    SingleLine(v) => {
      guard v.get_selection_start() is Some(start) else { return None }
      guard v.get_selection_end() is Some(end) else { return None }
      Some((start, end, v.get_selection_direction() == Some("backward")))
    }
  }
}

///|
fn Element::active(self : Element) -> Bool {
  guard input_document().get_active_element() is Some(active) else {
    return false
  }
  active
  .to_node()
  .is_same_node(
    Some(
      match self {
        Multiline(v) => v.to_node()
        SingleLine(v) => v.to_node()
      },
    ),
  )
}

///|
fn input_scroll(value : @input_dom.HTMLInputElement) -> Int {
  value.to_element().get_scroll_left().to_int()
}

///|
fn editor_scroll(value : @input_dom.HTMLTextAreaElement) -> Int {
  value.to_element().get_scroll_top().to_int()
}

///|
fn input_document_target() -> @input_dom.EventTarget {
  input_document().to_event_target()
}

///|
pub fn textarea(id : String) -> @input_dom.HTMLTextAreaElement? {
  guard input_document().get_element_by_id(id) is Some(v) else { return None }
  @input_dom.HTMLTextAreaElement::from_js_value_opt(v.to_js_value())
}

///|
pub fn input(id : String) -> @input_dom.HTMLInputElement? {
  guard input_document().get_element_by_id(id) is Some(v) else { return None }
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

///|
pub fn document() -> @input_dom.Document {
  input_document()
}

///|
pub fn document_target() -> @input_dom.EventTarget {
  input_document_target()
}
