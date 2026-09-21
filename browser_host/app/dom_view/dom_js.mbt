///|
pub fn element(id : String) -> @input_dom.HTMLElement {
  let element = @input_binding.document().get_element_by_id(id).unwrap()
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
pub fn text(element : @input_dom.HTMLElement, value : String) -> Unit {
  element.to_node().set_text_content(Some(value))
}

///|
pub fn button(id : String, label : String, enabled : Bool) -> Unit {
  let element = element(id)
  let button = @input_dom.HTMLButtonElement::from_js_value_opt(
    element.to_js_value(),
  ).unwrap()
  button.set_disabled(!enabled)
  text(element, label)
}
