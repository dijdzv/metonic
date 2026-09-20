///|
fn host_set_timeout(callback : () -> Unit, delay : Int) -> Int {
  input_window()
  .set_timeout_with_function(
    http_timer_handler(callback),
    delay,
    @input_dom.JsValue::undefined(),
  )
  .unwrap()
}

///|
fn host_clear_timeout(timer : Int) -> Unit {
  input_window().clear_timeout_with_id(timer)
}

///|
fn host_notify(kind : String) -> Unit {
  ignore(input_document_target().dispatch_event(@input_dom.Event::new(kind)))
}

///|
fn host_element(id : String) -> @input_dom.HTMLElement {
  let element = input_document().get_element_by_id(id).unwrap()
  @input_dom.HTMLElement::from_js_value_opt(element.to_js_value()).unwrap()
}

///|
fn host_offset(element : @input_dom.HTMLElement) -> (Int, Int) {
  (element.get_offset_left(), element.get_offset_top())
}

///|
fn host_class(element : @input_dom.HTMLElement, name : String) -> Unit {
  element.to_element().get_class_list().add(name).unwrap()
}

///|
fn host_style(
  element : @input_dom.HTMLElement,
  property : String,
  value : String,
) -> Unit {
  element
  .get_style()
  .to_css_style_declaration()
  .set_property(property, value)
  .unwrap()
}

///|
fn host_text(element : @input_dom.HTMLElement, value : String) -> Unit {
  element.to_node().set_text_content(Some(value))
}

///|
extern "js" fn http_timer_handler(callback : () -> Unit) -> @input_dom.Function =
  #| callback => callback
