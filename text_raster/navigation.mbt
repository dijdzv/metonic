///|
pub fn vertical_position(
  engine : Engine,
  text : String,
  offset : Int,
  down : Bool,
  preferred_x : Int?,
) -> (Int, Int?)? {
  vertical_caret(engine, text, offset, down, preferred_x, after=false).map(result => {
    (result.0, result.2)
  })
}

///|
pub fn vertical_caret(
  engine : Engine,
  text : String,
  offset : Int,
  down : Bool,
  preferred_x : Int?,
  after? : Bool = false,
) -> (Int, Bool, Int?)? {
  guard engine.text == text &&
    @text_position.utf16_to_scalar(text, offset) is Some(_) else {
    return None
  }
  guard engine.layout is Some(buffer) else { return None }
  guard buffer.cursor_motion(
      selection_cursor(text, offset, after~),
      preferred_x,
      if down {
        @cosmic.Motion::Down
      } else {
        @cosmic.Motion::Up
      },
    )
    is Some((cursor, x)) else {
    return None
  }
  let mut base = 0
  let mut line_index = 0
  for line in text.split("\n") {
    if line_index == cursor.line {
      let target = base + cursor.index
      guard cursor.index >= 0 &&
        cursor.index <= line.length() &&
        @text_position.utf16_to_scalar(text, target) is Some(_) else {
        return None
      }
      return Some((target, cursor.affinity.after(), x))
    }
    base += line.length() + 1
    line_index += 1
  }
  None
}
