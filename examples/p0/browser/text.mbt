///|
priv struct TextState {
  mut engine : @raster.Engine?
  mut font_bytes : FixedArray[Byte]?
  mut font_expected : Int
  mut font_received : Int
  mut font_pending : Bool
  mut text_units : Array[UInt16]
  mut text_expected : Int
  mut text_received : Int
  mut text_pending : Bool
  mut output : Bytes?
  mut output_width : Int
}

///|
let bridge : TextState = {
  engine: None,
  font_bytes: None,
  font_expected: 0,
  font_received: 0,
  font_pending: false,
  text_units: [],
  text_expected: 0,
  text_received: 0,
  text_pending: false,
  output: None,
  output_width: 0,
}

///|
fn clear_font() -> Unit {
  bridge.font_bytes = None
  bridge.font_expected = 0
  bridge.font_received = 0
  bridge.font_pending = false
}

///|
fn clear_text() -> Unit {
  bridge.text_units = []
  bridge.text_expected = 0
  bridge.text_received = 0
  bridge.text_pending = false
}

///|
fn prepare_font(length : Int) -> Bool {
  rendered_editor.val = None
  clear_font()
  clear_text()
  bridge.engine = None
  bridge.output = None
  bridge.output_width = 0
  length >= 1 && length <= 16777216
}

///|
#export_name("font_begin")
pub fn font_begin(length : Int) -> Int {
  if !prepare_font(length) {
    0
  } else {
    bridge.font_bytes = Some(FixedArray::make(length, b'\x00'))
    bridge.font_expected = length
    bridge.font_pending = true
    1
  }
}

///|
pub fn font_receive(bytes : FixedArray[Byte]) -> Int {
  if !prepare_font(bytes.length()) {
    return 0
  }
  bridge.font_bytes = Some(bytes)
  bridge.font_expected = bytes.length()
  bridge.font_received = bytes.length()
  bridge.font_pending = true
  font_commit()
}

///|
#export_name("font_put")
pub fn font_put(word : Int) -> Int {
  if !bridge.font_pending {
    0
  } else {
    match bridge.font_bytes {
      None => 0
      Some(bytes) =>
        if bridge.font_received >= bridge.font_expected {
          0
        } else {
          let mut i = 0
          while i < 4 && bridge.font_received < bridge.font_expected {
            bytes[bridge.font_received] = ((word >> (i * 8)) & 255).to_byte()
            bridge.font_received += 1
            i += 1
          }
          1
        }
    }
  }
}

///|
#export_name("font_commit")
pub fn font_commit() -> Int {
  if !bridge.font_pending {
    0
  } else {
    match bridge.font_bytes {
      None => 0
      Some(bytes) =>
        if bridge.font_received != bridge.font_expected {
          clear_font()
          0
        } else {
          let result = @raster.create(Bytes::from_array(bytes[:]))
          clear_font()
          match result {
            None => 0
            Some(value) => {
              bridge.engine = Some(value)
              1
            }
          }
        }
    }
  }
}

///|
#export_name("text_begin")
pub fn text_begin(length : Int) -> Int {
  clear_text()
  if length < 0 || length > 1024 {
    0
  } else {
    bridge.text_units = Array::make(length, (0).to_uint16())
    bridge.text_expected = length
    bridge.text_pending = true
    1
  }
}

///|
#export_name("text_put")
pub fn text_put(unit : Int) -> Int {
  if !bridge.text_pending ||
    unit < 0 ||
    unit > 65535 ||
    bridge.text_received >= bridge.text_expected {
    0
  } else {
    bridge.text_units[bridge.text_received] = unit.to_uint16()
    bridge.text_received += 1
    1
  }
}

///|
fn decode_text() -> String? {
  let chars : Array[Char] = []
  let mut i = 0
  while i < bridge.text_units.length() {
    let unit = bridge.text_units[i].to_int()
    if unit >= 0xD800 && unit <= 0xDBFF {
      if i + 1 >= bridge.text_units.length() {
        return None
      }
      let low = bridge.text_units[i + 1].to_int()
      if low < 0xDC00 || low > 0xDFFF {
        return None
      }
      chars.push(
        (0x10000 + ((unit - 0xD800) << 10) + low - 0xDC00).unsafe_to_char(),
      )
      i += 2
    } else if unit >= 0xDC00 && unit <= 0xDFFF {
      return None
    } else {
      chars.push(unit.unsafe_to_char())
      i += 1
    }
  }
  Some(String::from_array(chars))
}

///|
#export_name("text_commit")
pub fn text_commit(width : Int) -> Int {
  rendered_editor.val = None
  if !bridge.text_pending ||
    bridge.text_received != bridge.text_expected ||
    width < 1 ||
    width > 1024 {
    clear_text()
    0
  } else {
    match decode_text() {
      None => {
        clear_text()
        0
      }
      Some(text) =>
        match bridge.engine {
          None => {
            clear_text()
            0
          }
          Some(value) => {
            bridge.output = Some(@raster.render(value, text, width, 96))
            bridge.output_width = width
            clear_text()
            1
          }
        }
    }
  }
}

///|
#export_name("text_pixel")
pub fn text_pixel(index : Int) -> Int {
  match bridge.output {
    None => -1
    Some(bytes) =>
      if index < 0 || index >= bytes.length() / 4 {
        -1
      } else {
        bytes[index * 4].to_int() |
        (bytes[index * 4 + 1].to_int() << 8) |
        (bytes[index * 4 + 2].to_int() << 16) |
        (bytes[index * 4 + 3].to_int() << 24)
      }
  }
}

///|
#export_name("text_width")
pub fn text_width() -> Int {
  bridge.output_width
}

///|
#export_name("text_dispose")
pub fn text_dispose() -> Unit {
  view_layers.val = []
  rendered_editor.val = None
  clear_font()
  clear_text()
  bridge.engine = None
  bridge.output = None
  bridge.output_width = 0
}
