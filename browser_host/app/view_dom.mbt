///|
#export_name("view_place")
pub fn view_place() -> Unit {
  let (left, top) = host_offset(host_element("canvas"))
  for
    entry in [
      (0, "text-input"),
      (1, "rpc-load"),
      (3, "task-start"),
      (4, "task-cancel"),
      (6, "rpc-user"),
    ] {
    let (element, id) = entry
    let target = host_element(id)
    if element == 6 {
      host_class(target, "gpu-input")
    } else if element != 0 {
      host_class(target, "gpu-button")
    }
    host_style(
      target,
      "left",
      (left + @app.view_field(element, 0)).to_string() + "px",
    )
    host_style(
      target,
      "top",
      (top + @app.view_field(element, 1)).to_string() + "px",
    )
    host_style(target, "width", @app.view_field(element, 2).to_string() + "px")
    host_style(target, "height", @app.view_field(element, 3).to_string() + "px")
  }
  host_text(host_element("rpc-load"), @app.view_request_label())
}
