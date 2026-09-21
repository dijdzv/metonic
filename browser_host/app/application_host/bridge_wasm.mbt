///|
type Transfer = String

///|
fn rejected_font() -> @font_loader.FontPromise = "metonic:application" "rejected_font"

///|
fn transfer(bytes : Bytes) -> Transfer {
  bytes.to_unchecked_string()
}

///|
fn dispatch(name : String) -> Unit {
  ignore(
    @input_binding.document_target().dispatch_event(
      @dom.Event::new(name, { bubbles: None, cancelable: None, composed: None, }),
    ),
  )
}

///|
fn make_bridge(
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
) -> Instance = "metonic:application" "create"
