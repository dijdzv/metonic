///|
#export_name("transfer_font_words")
pub fn transfer_font_words(
  bytes : FixedArray[Byte],
  put : (Int) -> Int,
) -> Bool {
  if bytes.length() == 0 || bytes.length() > 16777216 {
    return false
  }
  for index = 0; index < bytes.length(); index = index + 4 {
    let mut word = 0
    for shift = 0
        shift < 4 && index + shift < bytes.length()
        shift = shift + 1 {
      word = word | (bytes[index + shift].to_int() << (shift * 8))
    }
    if put(word) != 1 {
      return false
    }
  }
  true
}
