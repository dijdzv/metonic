///|
let editor_composition : Ref[@semantics.Composition?] = Ref(None)

///|
let editor_preview : Ref[String?] = Ref(None)

///|
#export_name("editor_composition_end")
pub fn editor_composition_end() -> Unit {
  if editor_composition.val is Some(value) {
    value.cancel()
  }
  editor_composition.val = None
  editor_preview.val = None
}

///|
#export_name("editor_composition_start")
pub fn editor_composition_start() -> Int {
  editor_composition_end()
  editor_composition.val = @semantics.begin_composition(application.val.editor)
  if editor_composition.val is Some(_) {
    1
  } else {
    0
  }
}

///|
#export_name("editor_composition_update")
pub fn editor_composition_update() -> Int {
  let text = if bridge.text_pending &&
    bridge.text_received == bridge.text_expected {
    decode_text()
  } else {
    None
  }
  clear_text()
  match (editor_composition.val, text) {
    (Some(composition), Some(text)) => {
      editor_preview.val = composition.preview(text)
      if editor_preview.val is Some(_) {
        1
      } else {
        0
      }
    }
    _ => 0
  }
}

///|
fn editor_display() -> String {
  if editor_preview.val is Some(text) {
    return text
  }
  let nodes = @semantics.snapshot(application.val.editor)
  if nodes.length() == 2 {
    nodes[1].value
  } else {
    ""
  }
}

///|
#export_name("editor_display_unit")
pub fn editor_display_unit(index : Int) -> Int {
  let text = editor_display()
  if index >= 0 && index < text.length() {
    text.code_unit_at(index).to_int()
  } else {
    -1
  }
}

///|
fn accept_editor(value : String, start : Int, end : Int) -> Bool {
  if editor_composition.val is Some(_) {
    return false
  }
  let nodes = @semantics.snapshot(application.val.editor)
  if nodes.length() != 2 ||
    start > end ||
    @text_position.utf16_to_scalar(value, start) is None ||
    @text_position.utf16_to_scalar(value, end) is None {
    return false
  }
  let reference = nodes[1].reference
  @semantics.set_text(application.val.editor, reference, value) == "" &&
  @semantics.set_selection(application.val.editor, reference, start, end) == ""
}

///|
#export_name("editor_commit")
pub fn editor_commit(start : Int, end : Int) -> Int {
  let value = if bridge.text_pending &&
    bridge.text_received == bridge.text_expected {
    decode_text()
  } else {
    None
  }
  clear_text()
  match value {
    Some(value) if accept_editor(value, start, end) => 1
    _ => 0
  }
}

///|
#export_name("editor_field")
pub fn editor_field(index : Int) -> Int {
  let nodes = @semantics.snapshot(application.val.editor)
  if nodes.length() != 2 {
    return -1
  }
  let node = nodes[1]
  match index {
    0 => node.value.length()
    1 => node.selection_start
    2 => node.selection_end
    3 => @semantics.revision(application.val.editor)
    4 => editor_display().length()
    5 => if editor_composition.val is Some(_) { 1 } else { 0 }
    _ => -1
  }
}

///|
#export_name("editor_unit")
pub fn editor_unit(index : Int) -> Int {
  let nodes = @semantics.snapshot(application.val.editor)
  if nodes.length() != 2 || index < 0 || index >= nodes[1].value.length() {
    -1
  } else {
    nodes[1].value.code_unit_at(index).to_int()
  }
}

///|
#export_name("editor_dispose")
pub fn editor_dispose() -> Unit {
  editor_composition_end()
  ignore(@semantics.dispose(application.val.editor))
  clear_text()
}
