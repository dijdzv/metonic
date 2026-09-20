///|
#export_name("view_place")
pub fn view_place() -> Unit {
  let placements : Array[@dom_view.Placement] = []
  for
    entry in [
      (0, "text-input"),
      (1, "rpc-load"),
      (3, "task-start"),
      (4, "task-cancel"),
      (6, "rpc-user"),
    ] {
    let (element, id) = entry
    placements.push({
      element: @dom_view.element(id),
      bounds: {
        x: @app.view_field(element, 0),
        y: @app.view_field(element, 1),
        width: @app.view_field(element, 2),
        height: @app.view_field(element, 3),
      },
      class_name: if element == 6 {
        Some("gpu-input")
      } else if element != 0 {
        Some("gpu-button")
      } else {
        None
      },
    })
  }
  @dom_view.place(@dom_view.element("canvas"), placements)
  @dom_view.text(@dom_view.element("rpc-load"), @app.view_request_label())
}
