///|
pub struct TextUnits {
  offsets : Array[Int]
  lengths : Bytes
}

///|
pub fn text_units(text : String) -> TextUnits? {
  guard @position.utf16_to_scalar(text, text.length()) is Some(_) else {
    return None
  }
  let offsets = [0]
  let lengths : Array[Byte] = []
  let mut index = 0
  while index < text.length() {
    let unit = text[index].to_int()
    if unit == 13 && index + 1 < text.length() && text[index + 1].to_int() == 10 {
      index += 2
      lengths.push(b'\x02')
    } else if unit >= 0xD800 && unit <= 0xDBFF {
      index += 2
      lengths.push(b'\x04')
    } else {
      index += 1
      lengths.push(
        (if unit <= 127 { 1 } else if unit <= 2047 { 2 } else { 3 }).to_byte(),
      )
    }
    offsets.push(index)
  }
  Some({ offsets, lengths: Bytes::makei(lengths.length(), i => lengths[i]), })
}

///|
pub fn TextUnits::character_at(self : TextUnits, utf16 : Int) -> Int? {
  for index in 0..<self.offsets.length() {
    if self.offsets[index] == utf16 {
      return Some(index)
    }
  }
  None
}

///|
pub fn TextUnits::utf16_at(self : TextUnits, character : Int) -> Int? {
  if character < 0 || character >= self.offsets.length() {
    None
  } else {
    Some(self.offsets[character])
  }
}
