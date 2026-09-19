///|
#export_name("view_place")
pub fn view_place() -> Unit {
  let document = @dom.document()
  let canvas : @dom.HTMLElement = document
    .get_element_by_id("canvas")
    .unsafe_into()
  let left = canvas.offset_left()
  let top = canvas.offset_top()
  for
    entry in [
      (0, "text-input"),
      (1, "rpc-load"),
      (3, "task-start"),
      (4, "task-cancel"),
      (6, "rpc-user"),
    ] {
    let (element, id) = entry
    let target : @dom.HTMLElement = document.get_element_by_id(id).unsafe_into()
    if element == 6 {
      target.class_list().add(["gpu-input"])
    } else if element != 0 {
      target.class_list().add(["gpu-button"])
    }
    let style = target.style()
    style.set_property(
      "left",
      (left + @app.view_field(element, 0)).to_string() + "px",
    )
    style.set_property(
      "top",
      (top + @app.view_field(element, 1)).to_string() + "px",
    )
    style.set_property("width", @app.view_field(element, 2).to_string() + "px")
    style.set_property("height", @app.view_field(element, 3).to_string() + "px")
  }
  document
  .get_element_by_id("rpc-load")
  .set_text_content(@app.view_request_label())
}
