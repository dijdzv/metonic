///|
pub(all) struct Placement {
  element : @input_dom.HTMLElement
  bounds : @view.Bounds
  class_name : String?
}

///|
pub fn place(
  anchor : @input_dom.HTMLElement,
  entries : Array[Placement],
) -> Unit {
  let (left, top) = host_offset(anchor)
  for entry in entries {
    if entry.class_name is Some(name) {
      host_class(entry.element, name)
    }
    let bounds = entry.bounds
    host_style(entry.element, "left", (left + bounds.x).to_string() + "px")
    host_style(entry.element, "top", (top + bounds.y).to_string() + "px")
    host_style(entry.element, "width", bounds.width.to_string() + "px")
    host_style(entry.element, "height", bounds.height.to_string() + "px")
  }
}
