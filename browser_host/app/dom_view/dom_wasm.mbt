///|
pub fn element(id : String) -> @input_dom.HTMLElement {
  @input_dom.HTMLElement::from_element_opt(
    @input_binding.document().get_element_by_id(id).unwrap(),
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
pub fn text(element : @input_dom.HTMLElement, value : String) -> Unit {
  element.set_text_content(Some(value))
}
