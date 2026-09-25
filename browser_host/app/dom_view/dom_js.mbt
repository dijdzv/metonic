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
pub fn checkbox(
  id : String,
  label : String,
  enabled : Bool,
  checked : Bool,
  invalid : Bool,
) -> Unit {
  let child = element(id)
  let button = @input_dom.HTMLButtonElement::from_js_value_opt(
    child.to_js_value(),
  ).unwrap()
  button.set_disabled(!enabled)
  text(child, label)
  child
  .to_element()
  .set_attribute(
    "role",
    @input_dom.TrustedTypeOrString::from_string("checkbox"),
  )
  .unwrap()
  child
  .to_element()
  .set_attribute(
    "aria-checked",
    @input_dom.TrustedTypeOrString::from_string(checked.to_string()),
  )
  .unwrap()
  child
  .to_element()
  .set_attribute(
    "aria-invalid",
    @input_dom.TrustedTypeOrString::from_string(invalid.to_string()),
  )
  .unwrap()
}

///|
pub fn list(id : String, label : String, owns : String) -> Unit {
  let child = element(id)
  let dom = child.to_element()
  dom
  .set_attribute("role", @input_dom.TrustedTypeOrString::from_string("listbox"))
  .unwrap()
  dom
  .set_attribute(
    "aria-label",
    @input_dom.TrustedTypeOrString::from_string(label),
  )
  .unwrap()
  dom
  .set_attribute("aria-owns", @input_dom.TrustedTypeOrString::from_string(owns))
  .unwrap()
  host_style(child, "pointer-events", "none")
}

///|
pub fn list_item(
  id : String,
  label : String,
  selected : Bool,
  enabled : Bool,
) -> Unit {
  let child = element(id)
  let dom = child.to_element()
  text(child, label)
  dom
  .set_attribute("role", @input_dom.TrustedTypeOrString::from_string("option"))
  .unwrap()
  dom
  .set_attribute(
    "aria-selected",
    @input_dom.TrustedTypeOrString::from_string(selected.to_string()),
  )
  .unwrap()
  dom
  .set_attribute(
    "aria-disabled",
    @input_dom.TrustedTypeOrString::from_string((!enabled).to_string()),
  )
  .unwrap()
  dom
  .set_attribute(
    "tabindex",
    @input_dom.TrustedTypeOrString::from_string(
      if enabled {
        "0"
      } else {
        "-1"
      },
    ),
  )
  .unwrap()
  host_style(child, "color", "transparent")
}

///|
pub fn on_keydown(
  child : @input_dom.HTMLElement,
  callback : (String) -> Bool,
) -> () -> Unit {
  let target = child.to_event_target()
  let listener = @input_dom.EventListener::from_fn(event => {
    guard event.as_keyboard_event() is Some(key) && !key.get_is_composing() else {
      return
    }
    if callback(key.get_key()) {
      event.prevent_default()
      event.stop_propagation()
    }
  })
  target.add_event_listener("keydown", Some(listener))
  () => target.remove_event_listener("keydown", Some(listener))
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

///|
pub fn on_focus(
  child : @input_dom.HTMLElement,
  callback : () -> Unit,
) -> () -> Unit {
  let target = child.to_event_target()
  let listener = @input_dom.EventListener::from_fn(_ => callback())
  target.add_event_listener("focus", Some(listener))
  () => target.remove_event_listener("focus", Some(listener))
}

///|
pub fn on_wheel(
  child : @input_dom.HTMLElement,
  canvas : @input_dom.HTMLElement,
  callback : (Int, Int, Int) -> Bool,
) -> () -> Unit {
  let target = child.to_event_target()
  let listener = @input_dom.EventListener::from_fn(event => {
    guard event.as_wheel_event() is Some(wheel) else { return }
    let mouse = wheel.to_mouse_event()
    if mouse.get_ctrl_key() {
      return
    }
    let element = canvas.to_element()
    let rect = element.get_bounding_client_rect().to_dom_rect_read_only()
    let delta = wheel_pixels(
      wheel.get_delta_y(),
      wheel.get_delta_mode(),
      element.get_client_height(),
    )
    if callback(
        mouse.get_client_x() - rect.get_left().to_int(),
        mouse.get_client_y() - rect.get_top().to_int(),
        delta,
      ) {
      event.prevent_default()
      event.stop_propagation()
    }
  })
  target.add_event_listener("wheel", Some(listener))
  () => target.remove_event_listener("wheel", Some(listener))
}
