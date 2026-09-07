///|
/// Bounded, byte-oriented CLI line framer. UTF-8 decoding belongs to consumers.
pub(all) enum InputLine {
  Line(Bytes)
  TooLong
}

///|
pub struct Lines {
  mut buffer : Array[Byte]
  mut oversize : Bool
  mut saw_cr : Bool
}

///|
pub fn Lines::new() -> Lines {
  { buffer: [], oversize: false, saw_cr: false, }
}

///|
fn Lines::flush(self : Lines, output : Array[InputLine]) -> Unit {
  if self.oversize {
    output.push(TooLong)
  } else {
    output.push(Line(Bytes::from_array(self.buffer)))
  }
  self.buffer = []
  self.oversize = false
}

///|
fn Lines::consume_byte(
  self : Lines,
  byte : Byte,
  output : Array[InputLine],
) -> Unit {
  if byte == b'\n' {
    self.flush(output)
  } else if byte == b'\r' {
    self.flush(output)
    self.saw_cr = true
  } else if self.oversize {
    ()
  } else if self.buffer.length() < 4095 {
    self.buffer.push(byte)
  } else {
    self.oversize = true
  }
}

///|
/// Feed arbitrary chunks. CRLF produces one delimiter.
pub fn Lines::feed(self : Lines, chunk : Bytes) -> Array[InputLine] {
  let output : Array[InputLine] = []
  for byte in chunk.iter() {
    if self.saw_cr {
      self.saw_cr = false
      if byte == b'\n' {
        continue
      }
    }
    self.consume_byte(byte, output)
  }
  output
}

///|
/// Finish the stream, emitting one unterminated non-empty line if present.
pub fn Lines::finish(self : Lines) -> Array[InputLine] {
  let output : Array[InputLine] = []
  if self.buffer.length() > 0 || self.oversize {
    self.flush(output)
  }
  self.saw_cr = false
  output
}
