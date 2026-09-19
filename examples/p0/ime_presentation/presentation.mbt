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
