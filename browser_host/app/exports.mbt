///|
#export_name("init")
pub fn initialize() -> Unit {
  @app.reset_state()
}

///|
#export_name("editor_field")
pub fn editor_field(index : Int) -> Int {
  @app.editor_field(index)
}

///|
#export_name("composition_cursor")
pub fn composition_cursor(query : Bool, cursor : Int) -> Int {
  @app.composition_cursor(query, cursor)
}

///|
#export_name("editor_composition_end")
pub fn editor_composition_end() -> Unit {
  @app.editor_composition_end()
}

///|
#export_name("editor_dispose")
pub fn editor_dispose() -> Unit {
  @app.editor_dispose()
}

///|
#export_name("query_composition_end")
pub fn query_composition_end() -> Unit {
  @app.query_composition_end()
}

///|
#export_name("activate")
pub fn activate() -> Unit {
  @app.activate()
}

///|
#export_name("text_dispose")
pub fn text_dispose() -> Unit {
  @app.text_dispose()
}

///|
#export_name("editor_composition_start")
pub fn editor_composition_start() -> Int {
  @app.editor_composition_start()
}

///|
#export_name("editor_composition_update")
pub fn editor_composition_update() -> Int {
  @app.editor_composition_update()
}

///|
#export_name("query_composition_start")
pub fn query_composition_start() -> Int {
  @app.query_composition_start()
}

///|
#export_name("query_composition_update")
pub fn query_composition_update() -> Int {
  @app.query_composition_update()
}

///|
#export_name("task_begin")
pub fn task_begin() -> Int {
  @app.task_begin()
}

///|
#export_name("task_movement_target")
pub fn task_movement_target() -> Int {
  @app.task_movement_target()
}

///|
#export_name("task_cancel")
pub fn task_cancel() -> Int {
  @app.task_cancel()
}

///|
#export_name("task_dispose")
pub fn task_dispose() -> Int {
  @app.task_dispose()
}

///|
#export_name("text_height")
pub fn text_height() -> Int {
  @app.text_height()
}

///|
#export_name("view_layer_count")
pub fn view_layer_count() -> Int {
  @app.view_layer_count()
}

///|
#export_name("rpc_request")
pub fn rpc_request() -> Int {
  @app.rpc_request()
}

///|
#export_name("font_commit")
pub fn font_commit() -> Int {
  @app.font_commit()
}

///|
#export_name("text_width")
pub fn text_width() -> Int {
  @app.text_width()
}

///|
#export_name("editor_display_unit")
pub fn editor_display_unit(index : Int) -> Int {
  @app.editor_display_unit(index)
}

///|
#export_name("editor_unit")
pub fn editor_unit(index : Int) -> Int {
  @app.editor_unit(index)
}

///|
#export_name("task_field")
pub fn task_field(index : Int) -> Int {
  @app.task_field(index)
}

///|
#export_name("field")
pub fn field(index : Int) -> Int {
  @app.field(index)
}

///|
#export_name("view_label_unit")
pub fn view_label_unit(index : Int) -> Int {
  @app.view_label_unit(index)
}

///|
#export_name("text_pixel")
pub fn text_pixel(index : Int) -> Int {
  @app.text_pixel(index)
}

///|
#export_name("editor_commit")
pub fn editor_commit(start : Int, end : Int) -> Int {
  @app.editor_commit(start, end)
}

///|
#export_name("query_commit")
pub fn query_commit(start : Int, end : Int) -> Int {
  @app.query_commit(start, end)
}

///|
#export_name("task_complete")
pub fn task_complete(id : Int, value : Int) -> Int {
  @app.task_complete(id, value)
}

///|
#export_name("task_fail")
pub fn task_fail(id : Int, code : Int) -> Int {
  @app.task_fail(id, code)
}

///|
#export_name("resize")
pub fn resize(width : Int, height : Int) -> Int {
  @app.resize(width, height)
}

///|
#export_name("move_to")
pub fn move_to(x : Int, y : Int) -> Int {
  @app.move_to(x, y)
}

///|
#export_name("editor_render")
pub fn editor_render(viewport_width : Int) -> Int {
  @app.editor_render(viewport_width)
}

///|
#export_name("view_layer_field")
pub fn view_layer_field(layer : Int, field : Int) -> Int {
  @app.view_layer_field(layer, field)
}

///|
#export_name("view_layer_pixel")
pub fn view_layer_pixel(layer : Int, index : Int) -> Int {
  @app.view_layer_pixel(layer, index)
}

///|
#export_name("view_field")
pub fn view_field(element : Int, field : Int) -> Int {
  @app.view_field(element, field)
}

///|
#export_name("view_focus")
pub fn view_focus(element : Int) -> Int {
  @app.view_focus(element)
}

///|
#export_name("rpc_begin_input")
pub fn rpc_begin_input(length : Int) -> Int {
  @app.rpc_begin_input(length)
}

///|
#export_name("rpc_put")
pub fn rpc_put(value : Int) -> Int {
  @app.rpc_put(value)
}

///|
#export_name("rpc_output_length")
pub fn rpc_output_length(kind : Int) -> Int {
  @app.rpc_output_length(kind)
}

///|
#export_name("rpc_output_byte")
pub fn rpc_output_byte(kind : Int, index : Int) -> Int {
  @app.rpc_output_byte(kind, index)
}

///|
#export_name("rpc_response")
pub fn rpc_response(id : Int, status : Int) -> Int {
  @app.rpc_response(id, status)
}

///|
#export_name("rpc_transport_error")
pub fn rpc_transport_error(id : Int, code : Int) -> Int {
  @app.rpc_transport_error(id, code)
}

///|
#export_name("font_begin")
pub fn font_begin(length : Int) -> Int {
  @app.font_begin(length)
}

///|
#export_name("font_put")
pub fn font_put(word : Int) -> Int {
  @app.font_put(word)
}

///|
#export_name("text_begin")
pub fn text_begin(length : Int) -> Int {
  @app.text_begin(length)
}

///|
#export_name("text_put")
pub fn text_put(unit : Int) -> Int {
  @app.text_put(unit)
}

///|
#export_name("text_commit")
pub fn text_commit(width : Int) -> Int {
  @app.text_commit(width)
}
