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

///|
pub fn create_control(
  parent : @input_dom.HTMLElement,
  id : String,
  tag : String,
) -> @input_dom.HTMLElement {
  let created = @input_binding.document().create_element(tag).unwrap()
  created.set_id(id)
  if tag == "button" {
    created
    .set_attribute(
      "type",
      @input_dom.TrustedTypeOrString::from_string("button"),
    )
    .unwrap()
  }
  if tag == "input" || tag == "textarea" {
    created
    .set_attribute(
      "maxlength",
      @input_dom.TrustedTypeOrString::from_string("1024"),
    )
    .unwrap()
  }
  let child = @input_dom.HTMLElement::from_js_value_opt(created.to_js_value()).unwrap()
  ignore(parent.to_node().append_child(child.to_node()).unwrap())
  host_style(child, "position", "absolute")
  if tag == "span" {
    host_style(child, "color", "transparent")
    host_style(child, "pointer-events", "none")
  }
  child
}

///|
pub fn remove_control(
  parent : @input_dom.HTMLElement,
  child : @input_dom.HTMLElement,
) -> Unit {
  ignore(parent.to_node().remove_child(child.to_node()).unwrap())
}

///|
pub fn order_control(
  parent : @input_dom.HTMLElement,
  child : @input_dom.HTMLElement,
) -> Unit {
  parent.to_element().move_before(child.to_node(), None).unwrap()
}

///|
pub fn label(child : @input_dom.HTMLElement, value : String) -> Unit {
  child
  .to_element()
  .set_attribute(
    "aria-label",
    @input_dom.TrustedTypeOrString::from_string(value),
  )
  .unwrap()
}

///|
pub fn on_click(
  child : @input_dom.HTMLElement,
  callback : () -> Unit,
) -> () -> Unit {
  let target = child.to_event_target()
  let listener = @input_dom.EventListener::from_fn(_ => callback())
  target.add_event_listener("click", Some(listener))
  () => target.remove_event_listener("click", Some(listener))
}

///|
pub fn claim_root(root : @input_dom.HTMLElement) -> Bool {
  let element = root.to_element()
  if element.has_attribute("data-metonic-owner") {
    return false
  }
  element
  .set_attribute(
    "data-metonic-owner",
    @input_dom.TrustedTypeOrString::from_string("active"),
  )
  .unwrap()
  true
}

///|
pub fn release_root(root : @input_dom.HTMLElement) -> Unit {
  root.to_element().remove_attribute("data-metonic-owner")
}
