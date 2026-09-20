///|
fn host_set_timeout(callback : () -> Unit, delay : Int) -> Int {
  input_window().set_timeout(@input_dom.TimeoutCallback::new(callback), delay)
}

///|
fn host_clear_timeout(timer : Int) -> Unit {
  input_window().clear_timeout(timer)
}

///|
fn host_notify(kind : String) -> Unit {
  ignore(
    input_document_target().dispatch_event(
      @input_dom.Event::new(kind, {
        bubbles: None,
        cancelable: None,
        composed: None,
      }),
    ),
  )
}

///|
fn host_element(id : String) -> @input_dom.HTMLElement {
  @input_dom.HTMLElement::from_element_opt(
    input_document().get_element_by_id(id).unwrap(),
  ).unwrap()
}

///|
fn host_offset(element : @input_dom.HTMLElement) -> (Int, Int) {
  (element.offset_left(), element.offset_top())
}

///|
fn host_class(element : @input_dom.HTMLElement, name : String) -> Unit {
  element.class_list().add(name)
}

///|
fn host_style(
  element : @input_dom.HTMLElement,
  property : String,
  value : String,
) -> Unit {
  element.style().set_property(property, value, "")
}

///|
fn host_text(element : @input_dom.HTMLElement, value : String) -> Unit {
  element.set_text_content(Some(value))
}
