///|
#export_name("query_commit")
pub fn query_commit(start : Int, end : Int) -> Int {
  let value = if bridge.text_pending &&
    bridge.text_received == bridge.text_expected {
    decode_text()
  } else {
    None
  }
  clear_text()
  guard value is Some(value) else { return 0 }
  let model = application.val
  if start > end ||
    @text_position.utf16_to_scalar(value, start) is None ||
    @text_position.utf16_to_scalar(value, end) is None {
    return 0
  }
  if @semantics.set_text(model.editor, model.query_input, value) == "" &&
    @semantics.set_selection(model.editor, model.query_input, start, end) == "" {
    1
  } else {
    0
  }
}
