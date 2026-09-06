///|
fn valid_utf16(text : String) -> Bool {
  let mut i = 0
  while i < text.length() {
    let unit = text.at(i).to_int()
    if unit >= 0xD800 && unit <= 0xDBFF {
      if i + 1 >= text.length() {
        return false
      }
      let low = text.at(i + 1).to_int()
      if low < 0xDC00 || low > 0xDFFF {
        return false
      }
      i += 2
    } else if unit >= 0xDC00 && unit <= 0xDFFF {
      return false
    } else {
      i += 1
    }
  }
  true
}

///|
/// Convert a UTF-16 code-unit boundary to a UTF-8 byte boundary.
/// Offsets inside surrogate pairs, invalid strings, and out-of-range offsets return None.
pub fn utf16_to_utf8(text : String, offset : Int) -> Int? {
  if !valid_utf16(text) || offset < 0 || offset > text.length() {
    None
  } else {
    let mut u16 = 0
    let mut u8 = 0
    while u16 < text.length() {
      if u16 == offset {
        return Some(u8)
      }
      let unit = text.at(u16).to_int()
      if unit >= 0xD800 && unit <= 0xDBFF {
        if u16 + 1 >= text.length() {
          return None
        }
        let low = text.at(u16 + 1).to_int()
        if low < 0xDC00 || low > 0xDFFF {
          return None
        }
        if offset == u16 + 1 {
          return None
        }
        u16 += 2
        u8 += 4
      } else if unit >= 0xDC00 && unit <= 0xDFFF {
        return None
      } else {
        u16 += 1
        u8 += if unit <= 0x7F { 1 } else if unit <= 0x7FF { 2 } else { 3 }
      }
    }
    if offset == u16 {
      Some(u8)
    } else {
      None
    }
  }
}

///|
/// Convert a UTF-8 byte boundary to a UTF-16 code-unit boundary.
/// Only scalar boundaries are accepted; this does not convert graphemes or glyphs.
pub fn utf8_to_utf16(text : String, offset : Int) -> Int? {
  if !valid_utf16(text) || offset < 0 {
    None
  } else {
    let mut u16 = 0
    let mut u8 = 0
    while u16 < text.length() {
      if u8 == offset {
        return Some(u16)
      }
      let unit = text.at(u16).to_int()
      let width = if unit >= 0xD800 && unit <= 0xDBFF {
        if u16 + 1 >= text.length() {
          return None
        }
        let low = text.at(u16 + 1).to_int()
        if low < 0xDC00 || low > 0xDFFF {
          return None
        }
        4
      } else if unit >= 0xDC00 && unit <= 0xDFFF {
        return None
      } else if unit <= 0x7F {
        1
      } else if unit <= 0x7FF {
        2
      } else {
        3
      }
      if offset > u8 && offset < u8 + width {
        return None
      }
      u8 += width
      u16 += if width == 4 { 2 } else { 1 }
    }
    if offset == u8 {
      Some(u16)
    } else {
      None
    }
  }
}

///|
/// Convert a UTF-16 boundary to a scalar-value index.
/// The returned index is defined only at scalar boundaries.
pub fn utf16_to_scalar(text : String, offset : Int) -> Int? {
  if !valid_utf16(text) || offset < 0 || offset > text.length() {
    None
  } else {
    let mut u16 = 0
    let mut scalar = 0
    while u16 < text.length() {
      if u16 == offset {
        return Some(scalar)
      }
      let unit = text.at(u16).to_int()
      if unit >= 0xD800 && unit <= 0xDBFF {
        if u16 + 1 >= text.length() {
          return None
        }
        let low = text.at(u16 + 1).to_int()
        if low < 0xDC00 || low > 0xDFFF {
          return None
        }
        if offset == u16 + 1 {
          return None
        }
        u16 += 2
      } else if unit >= 0xDC00 && unit <= 0xDFFF {
        return None
      } else {
        u16 += 1
      }
      scalar += 1
    }
    if offset == u16 {
      Some(scalar)
    } else {
      None
    }
  }
}

///|
/// Convert a scalar-value boundary to a UTF-16 code-unit offset.
/// Only scalar boundaries are accepted; grapheme segmentation is intentionally excluded.
pub fn scalar_to_utf16(text : String, offset : Int) -> Int? {
  if !valid_utf16(text) || offset < 0 {
    None
  } else {
    let mut u16 = 0
    let mut scalar = 0
    while u16 < text.length() {
      if scalar == offset {
        return Some(u16)
      }
      let unit = text.at(u16).to_int()
      if unit >= 0xD800 && unit <= 0xDBFF {
        if u16 + 1 >= text.length() {
          return None
        }
        let low = text.at(u16 + 1).to_int()
        if low < 0xDC00 || low > 0xDFFF {
          return None
        }
        u16 += 2
      } else if unit >= 0xDC00 && unit <= 0xDFFF {
        return None
      } else {
        u16 += 1
      }
      scalar += 1
    }
    if scalar == offset {
      Some(u16)
    } else {
      None
    }
  }
}
