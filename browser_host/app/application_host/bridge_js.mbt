///|
type Transfer = Bytes

///|
extern "js" fn rejected_font() -> @font_loader.FontPromise =
  #| () => Promise.reject(new Error('Application is stopped'))

///|
fn transfer(bytes : Bytes) -> Transfer {
  bytes
}

///|
fn dispatch(name : String) -> Unit {
  ignore(@input_binding.document_target().dispatch_event(@dom.Event::new(name)))
}

///|
extern "js" fn make_bridge(
  load_font : () -> @font_loader.FontPromise,
  install_font : (@dom.ArrayBuffer) -> Int,
  start : (@dom.GPUDevice, String) -> Int,
  resize : (Int, Int) -> Int,
  render : () -> Int,
  activate : (Int) -> Int,
  layer_count : () -> Int,
  layer_field : (Int, Int) -> Int,
  layer_bytes : (Int) -> Transfer,
  upload_begin : () -> Unit,
  upload_layer : (Int, @dom.ArrayBufferView) -> Int,
  upload_commit : () -> Int,
  frame_begin : (@dom.GPUCanvasContext) -> Int,
  frame_text : (Int, @dom.ArrayBufferView) -> Int,
  frame_submit : () -> Int,
  frame_abort : () -> Unit,
  stop : () -> Unit,
  can_close : () -> Int,
  request_close : () -> Unit,
  close_ready : () -> Int,
) -> Instance =
  #| (load_font, install_font, start, resize, render, activate, layer_count, layer_field, layer_bytes, upload_begin, upload_layer, upload_commit, frame_begin, frame_text, frame_submit, frame_abort, stop, can_close, request_close, close_ready) => ({load_font, install_font, start, resize, render, activate, layer_count, layer_field, layer_bytes, upload_begin, upload_layer, upload_commit, frame_begin, frame_text, frame_submit, frame_abort, stop, can_close, request_close, close_ready})
