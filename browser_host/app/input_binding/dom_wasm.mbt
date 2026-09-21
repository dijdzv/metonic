///|
fn input_document() -> @input_dom.Document = "websys" "input_document"

///|
fn input_window() -> @input_dom.Window = "websys" "input_window"

///|
fn Element::target(self : Element) -> @input_dom.EventTarget {
  match self {
    Multiline(v) => v.as_event_target()
    SingleLine(v) => v.as_event_target()
  }
}

///|
pub fn Element::value(self : Element) -> String {
  match self {
    Multiline(v) => v.value()
    SingleLine(v) => v.value()
  }
}

///|
fn Element::selection(self : Element) -> (Int, Int, Bool)? {
  match self {
    Multiline(v) =>
      Some(
        (
          v.selection_start().reinterpret_as_int(),
          v.selection_end().reinterpret_as_int(),
          v.selection_direction() == "backward",
        ),
      )
    SingleLine(v) => {
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
fn Element::active(self : Element) -> Bool {
  guard input_document().active_element() is Some(active) else { return false }
  active.is_same_node(
    Some(
      match self {
        Multiline(v) => v.as_node()
        SingleLine(v) => v.as_node()
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
fn editor_scroll_limit(value : @input_dom.HTMLTextAreaElement) -> Int {
  (value.scroll_height() - value.client_height()).max(0)
}

///|
fn editor_restore_scroll(
  value : @input_dom.HTMLTextAreaElement,
  offset : Int,
  at_end : Bool,
) -> Int {
  value.set_scroll_top(
    (if at_end { editor_scroll_limit(value) } else { offset }).to_double(),
  )
  editor_scroll(value)
}

///|
fn input_restore_scroll(
  value : @input_dom.HTMLInputElement,
  offset : Int,
) -> Int {
  value.set_scroll_left(offset.to_double())
  input_scroll(value)
}

///|
fn input_document_target() -> @input_dom.EventTarget {
  input_document().as_event_target()
}

///|
pub fn textarea(id : String) -> @input_dom.HTMLTextAreaElement? {
  guard input_document().get_element_by_id(id) is Some(v) else { return None }
  @input_dom.HTMLTextAreaElement::from_element_opt(v)
}

///|
pub fn input(id : String) -> @input_dom.HTMLInputElement? {
  guard input_document().get_element_by_id(id) is Some(v) else { return None }
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

///|
pub fn document() -> @input_dom.Document {
  input_document()
}

///|
pub fn document_target() -> @input_dom.EventTarget {
  input_document_target()
}
