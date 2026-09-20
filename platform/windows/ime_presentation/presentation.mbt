///|
pub fn display_cursor(text : String, cursor : Int, attributes : Bytes) -> Int {
  let cursor = if @text_position.utf16_to_utf8(text, cursor) is Some(_) {
    cursor
  } else {
    text.length()
  }
  // Missing or malformed metadata cannot distinguish conversion from input.
  if attributes.length() != text.length() {
    return cursor
  }
  for i in 0..<attributes.length() {
    if attributes[i].to_int() > 5 ||
      (
        i > 0 &&
        attributes[i] != attributes[i - 1] &&
        @text_position.utf16_to_utf8(text, i) is None
      ) {
      return cursor
    }
  }
  // A valid zero remains meaningful while editing unconverted text.
  if (cursor < attributes.length() && attributes[cursor] == b'\x00') ||
    (cursor > 0 && attributes[cursor - 1] == b'\x00') {
    cursor
  } else {
    text.length()
  }
}

///|
/// Interpret Windows IMM attributes indexed by UTF-16 code unit.
pub fn target_ranges(text : String, attributes : Bytes) -> Array[(Int, Int)] {
  let ranges : Array[(Int, Int)] = []
  if attributes.length() != text.length() {
    return ranges
  }
  let mut start = -1
  for i = 0; i <= attributes.length(); i = i + 1 {
    let target = i < attributes.length() &&
      (attributes[i] == b'\x01' || attributes[i] == b'\x03')
    if target && start < 0 {
      start = i
    } else if !target && start >= 0 {
      // A partial surrogate cannot be painted as a separate conversion target.
      if @text_position.utf16_to_utf8(text, start) is None ||
        @text_position.utf16_to_utf8(text, i) is None {
        return []
      }
      ranges.push((start, i))
      start = -1
    }
  }
  ranges
}
