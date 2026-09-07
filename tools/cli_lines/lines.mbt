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
  lf_only : Bool
}

///|
pub fn Lines::new(lf_only? : Bool = false) -> Lines {
  { buffer: [], oversize: false, saw_cr: false, lf_only, }
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
fn Lines::consume_lf_byte(
  self : Lines,
  byte : Byte,
  output : Array[InputLine],
) -> Unit {
  if byte == b'\n' {
    // A deferred CR is the CRLF terminator, so it must not enter the body.
    self.saw_cr = false
    self.flush(output)
  } else {
    if self.saw_cr {
      self.saw_cr = false
      if self.oversize {
        ()
      } else if self.buffer.length() < 4095 {
        self.buffer.push(b'\r')
      } else {
        self.oversize = true
      }
    }
    if byte == b'\r' {
      self.saw_cr = true
    } else if self.oversize {
      ()
    } else if self.buffer.length() < 4095 {
      self.buffer.push(byte)
    } else {
      self.oversize = true
    }
  }
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
  if self.lf_only {
    for byte in chunk.iter() {
      self.consume_lf_byte(byte, output)
    }
    return output
  }
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
  if self.lf_only {
    if self.saw_cr || self.buffer.length() > 0 || self.oversize {
      self.saw_cr = false
      self.flush(output)
    }
    return output
  }
  if self.buffer.length() > 0 || self.oversize {
    self.flush(output)
  }
  self.saw_cr = false
  output
}
