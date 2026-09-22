///|
pub(all) struct Placement {
  element : @input_dom.HTMLElement
  bounds : @view.Bounds
  class_name : String?
}

///|
fn wheel_pixels(delta : Double, mode : Int, height : Int) -> Int {
  if delta != delta {
    return 0
  }
  let factor = match mode {
    1 => 96.0
    2 => height.max(1).to_double()
    _ => 1.0
  }
  let pixels = delta * factor
  pixels.max(-1048576.0).min(1048576.0).to_int()
}

///|
pub fn clip(
  element : @input_dom.HTMLElement,
  bounds : @view.Bounds,
  clip : @view.Bounds?,
) -> Unit {
  let value = match clip {
    None => "none"
    Some(clip) =>
      match bounds.intersection(clip) {
        None => "inset(50%)"
        Some(visible) =>
          "inset(" +
          (visible.y - bounds.y).to_string() +
          "px " +
          (bounds.x + bounds.width - visible.x - visible.width).to_string() +
          "px " +
          (bounds.y + bounds.height - visible.y - visible.height).to_string() +
          "px " +
          (visible.x - bounds.x).to_string() +
          "px)"
      }
  }
  host_style(element, "clip-path", value)
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
