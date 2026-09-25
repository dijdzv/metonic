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

///|
pub fn button(id : String, label : String, enabled : Bool) -> Unit {
  let button = @input_dom.HTMLButtonElement::from_element_opt(
    @input_binding.document().get_element_by_id(id).unwrap(),
  ).unwrap()
  button.set_disabled(!enabled)
  text(element(id), label)
}

///|
pub fn checkbox(
  id : String,
  label : String,
  enabled : Bool,
  checked : Bool,
  invalid : Bool,
) -> Unit {
  let child = element(id)
  let button = @input_dom.HTMLButtonElement::from_element_opt(
    child.as_element(),
  ).unwrap()
  button.set_disabled(!enabled)
  text(child, label)
  child.set_attribute("role", "checkbox")
  child.set_attribute("aria-checked", checked.to_string())
  child.set_attribute("aria-invalid", invalid.to_string())
}

///|
pub fn create_control(
  parent : @input_dom.HTMLElement,
  id : String,
  tag : String,
) -> @input_dom.HTMLElement {
  let created = @input_binding.document().create_element(tag)
  created.set_id(id)
  if tag == "button" {
    created.set_attribute("type", "button")
  }
  if tag == "input" || tag == "textarea" {
    created.set_attribute("maxlength", "1024")
  }
  let child = @input_dom.HTMLElement::from_element_opt(created).unwrap()
  ignore(parent.append_child(child.as_node()))
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
  ignore(parent.remove_child(child.as_node()))
}

///|
pub fn order_control(
  parent : @input_dom.HTMLElement,
  child : @input_dom.HTMLElement,
) -> Unit {
  parent.move_before(child.as_node(), None)
}

///|
pub fn label(child : @input_dom.HTMLElement, value : String) -> Unit {
  child.set_attribute("aria-label", value)
}

///|
pub fn on_click(
  child : @input_dom.HTMLElement,
  callback : () -> Unit,
) -> () -> Unit {
  let target = child.as_event_target()
  let listener = @input_dom.EventListener::new(_ => callback())
  target.add_event_listener("click", listener, false)
  () => target.remove_event_listener("click", listener, false)
}

///|
pub fn claim_root(root : @input_dom.HTMLElement) -> Bool {
  if root.has_attribute("data-metonic-owner") {
    return false
  }
  root.set_attribute("data-metonic-owner", "active")
  true
}

///|
pub fn release_root(root : @input_dom.HTMLElement) -> Unit {
  root.remove_attribute("data-metonic-owner")
}

///|
pub fn on_focus(
  child : @input_dom.HTMLElement,
  callback : () -> Unit,
) -> () -> Unit {
  let target = child.as_event_target()
  let listener = @input_dom.EventListener::new(_ => callback())
  target.add_event_listener("focus", listener, false)
  () => target.remove_event_listener("focus", listener, false)
}

///|
pub fn on_wheel(
  child : @input_dom.HTMLElement,
  canvas : @input_dom.HTMLElement,
  callback : (Int, Int, Int) -> Bool,
) -> () -> Unit {
  let target = child.as_event_target()
  let listener = @input_dom.EventListener::new(event => {
    guard @input_dom.WheelEvent::from_event_opt(event) is Some(wheel) else {
      return
    }
    if wheel.ctrl_key() {
      return
    }
    let rect = canvas.get_bounding_client_rect()
    let delta = wheel_pixels(
      wheel.delta_y(),
      wheel.delta_mode().reinterpret_as_int(),
      canvas.client_height(),
    )
    if callback(
        wheel.client_x() - rect.left().to_int(),
        wheel.client_y() - rect.top().to_int(),
        delta,
      ) {
      event.prevent_default()
      event.stop_propagation()
    }
  })
  target.add_event_listener("wheel", listener, false)
  () => target.remove_event_listener("wheel", listener, false)
}
