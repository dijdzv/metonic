///|
fn stage_preedit(
  composition : @semantics.Composition,
  preedit : String,
  preview : Ref[String?],
  geometry : Ref[(Int, Int, Int)?],
) -> Int {
  match composition.presentation(preedit, preedit.length()) {
    Some((text, start, end, cursor)) => {
      preview.val = Some(text)
      geometry.val = Some((start, end, cursor))
      1
    }
    None => {
      preview.val = None
      geometry.val = None
      0
    }
  }
}

///|
#export_name("composition_cursor")
pub fn composition_cursor(query : Bool, cursor : Int) -> Int {
  let value = if bridge.text_pending &&
    bridge.text_received == bridge.text_expected {
    decode_text()
  } else {
    None
  }
  clear_text()
  guard value is Some(value) else { return 0 }
  input_cursor(query, value, cursor)
}

///|
pub fn input_cursor(query : Bool, value : String, cursor : Int) -> Int {
  if value.length() > 1024 {
    return 0
  }
  let composition = if query {
    query_composition.val
  } else {
    editor_composition.val
  }
  let preview = if query { query_preview } else { editor_preview }
  let geometry = if query {
    query_preedit_geometry
  } else {
    editor_preedit_geometry
  }
  guard composition is Some(composition) &&
    preview.val is Some(text) &&
    value == text &&
    geometry.val is Some((start, end, _)) else {
    return 0
  }
  guard composition.presentation(text[start:end].to_owned(), cursor - start)
    is Some((_, _, _, caret)) else {
    return 0
  }
  geometry.val = Some((start, end, caret))
  1
}

///|
pub fn input_dom_preview(query : Bool, value : String, cursor : Int) -> Int {
  let composition = if query {
    query_composition.val
  } else {
    editor_composition.val
  }
  guard value.length() <= 1024 &&
    @text_position.utf16_to_scalar(value, value.length()) is Some(_) &&
    @text_position.utf16_to_scalar(value, cursor) is Some(_) &&
    composition is Some(composition) &&
    composition.preview("") is Some(_) else {
    return 0
  }
  if input_cursor(query, value, cursor) == 1 {
    return 1
  }
  // A DOM selection does not identify an existing-text composition range.
  // Guessing that range from repeated characters can duplicate or erase text.
  let preview = if query { query_preview } else { editor_preview }
  let geometry = if query {
    query_preedit_geometry
  } else {
    editor_preedit_geometry
  }
  preview.val = Some(value)
  geometry.val = Some((cursor, cursor, cursor))
  1
}
