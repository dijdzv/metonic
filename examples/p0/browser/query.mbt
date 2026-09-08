///|
let query_composition : Ref[@semantics.Composition?] = Ref(None)

///|
let query_preview : Ref[String?] = Ref(None)

///|
let query_preedit_geometry : Ref[(Int, Int, Int)?] = Ref(None)

///|
#export_name("query_composition_end")
pub fn query_composition_end() -> Unit {
  if query_composition.val is Some(value) {
    value.cancel()
  }
  query_composition.val = None
  query_preview.val = None
  query_preedit_geometry.val = None
}

///|
#export_name("query_composition_start")
pub fn query_composition_start() -> Int {
  query_composition_end()
  query_composition.val = @semantics.begin_composition(
    application.val.editor,
    target=application.val.query_input,
  )
  if query_composition.val is Some(_) {
    1
  } else {
    0
  }
}

///|
#export_name("query_composition_update")
pub fn query_composition_update() -> Int {
  let text = if bridge.text_pending &&
    bridge.text_received == bridge.text_expected {
    decode_text()
  } else {
    None
  }
  clear_text()
  match text {
    Some(text) => input_preedit(true, text)
    _ => 0
  }
}

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
  input_commit(true, value, start, end)
}

///|
fn accept_query(value : String, start : Int, end : Int) -> Int {
  if query_composition.val is Some(_) {
    return 0
  }
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
