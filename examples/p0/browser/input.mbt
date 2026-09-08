///|
pub fn input_commit(
  query : Bool,
  value : String,
  start : Int,
  end : Int,
) -> Int {
  if value.length() > 1024 {
    return 0
  }
  if query {
    accept_query(value, start, end)
  } else if accept_editor(value, start, end) {
    1
  } else {
    0
  }
}

///|
pub fn input_preedit(query : Bool, value : String) -> Int {
  if value.length() > 1024 || @text_position.utf16_to_scalar(value, 0) is None {
    return 0
  }
  let composition = if query {
    query_composition.val
  } else {
    editor_composition.val
  }
  guard composition is Some(composition) else { return 0 }
  if query {
    stage_preedit(composition, value, query_preview, query_preedit_geometry)
  } else {
    stage_preedit(composition, value, editor_preview, editor_preedit_geometry)
  }
}
