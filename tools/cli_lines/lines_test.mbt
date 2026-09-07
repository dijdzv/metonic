///|
fn assert_line(value : InputLine, expected : Bytes) -> Unit raise Error {
  match value {
    Line(actual) => assert_eq(actual, expected)
    TooLong => fail("expected line")
  }
}

///|
test "accepts 4095 bytes and rejects 4096 with recovery" {
  let accepted = Lines::new()
  let accepted_input : Array[Byte] = Array::make(4095, b'a')
  accepted_input.push(b'\n')
  let accepted_out = accepted.feed(Bytes::from_array(accepted_input))
  assert_eq(accepted_out.length(), 1)
  assert_line(accepted_out[0], Bytes::from_array(Array::make(4095, b'a')))

  let lines = Lines::new()
  let exact : Array[Byte] = Array::make(4095, b'a')
  let exact_out = lines.feed(Bytes::from_array(exact))
  assert_eq(exact_out.length(), 0)
  let too_long = lines.feed(b"b\n")
  assert_eq(too_long.length(), 1)
  match too_long[0] {
    TooLong => ()
    Line(_) => fail("expected TooLong")
  }
  let recovered = lines.feed(b"ok\n")
  assert_eq(recovered.length(), 1)
  assert_line(recovered[0], b"ok")
}

///|
test "oversize EOF reports once and recovers" {
  let lines = Lines::new()
  let oversized : Array[Byte] = Array::make(4096, b'x')
  assert_eq(lines.feed(Bytes::from_array(oversized)).length(), 0)
  let first = lines.finish()
  assert_eq(first.length(), 1)
  match first[0] {
    TooLong => ()
    Line(_) => fail("expected TooLong at EOF")
  }
  assert_eq(lines.finish().length(), 0)
}

///|
test "fragments CRLF and bare CR" {
  let lines = Lines::new()
  assert_eq(lines.feed(b"a\r").length(), 1)
  let crlf = lines.feed(b"\nb\r\nc\n")
  assert_eq(crlf.length(), 2)
  assert_line(crlf[0], b"b")
  assert_line(crlf[1], b"c")
  assert_eq(lines.finish().length(), 0)
}

///|
test "handles multiple lines and empty lines" {
  let lines = Lines::new()
  let output = lines.feed(b"\nleft\n\nright\n")
  assert_eq(output.length(), 4)
  assert_line(output[0], b"")
  assert_line(output[1], b"left")
  assert_line(output[2], b"")
  assert_line(output[3], b"right")
}

///|
test "emits unterminated final line but not empty EOF" {
  let lines = Lines::new()
  let output = lines.feed(b"tail")
  assert_eq(output.length(), 0)
  let tail = lines.finish()
  assert_eq(tail.length(), 1)
  assert_line(tail[0], b"tail")
  assert_eq(lines.finish().length(), 0)
}

///|
test "chunking is equivalent" {
  let whole = Lines::new().feed(b"one\r\ntwo\nthree\r")
  let split = Lines::new()
  let first = split.feed(b"one\r")
  let second = split.feed(b"\ntwo\nthree\r")
  let tail = split.finish()
  assert_eq(first.length(), 1)
  assert_eq(second.length(), 2)
  assert_line(first[0], b"one")
  assert_line(second[0], b"two")
  assert_line(second[1], b"three")
  assert_eq(tail.length(), 0)
  assert_eq(whole.length(), 3)
}

///|
test "LF-only mode strips fragmented CRLF and preserves internal CR" {
  let lines = Lines::new(lf_only=true)
  assert_eq(lines.feed(b"a\r").length(), 0)
  let output = lines.feed(b"\nb\rc\n")
  assert_eq(output.length(), 2)
  assert_line(output[0], b"a")
  assert_line(output[1], b"b\rc")

  let json = Lines::new(lf_only=true)
  let json_output = json.feed(b"{\"value\":\r1}\n")
  assert_eq(json_output.length(), 1)
  assert_line(json_output[0], b"{\"value\":\r1}")
}

///|
test "LF-only mode accepts 4095 body with CRLF and recovers after 4096" {
  let accepted = Lines::new(lf_only=true)
  let body : Array[Byte] = Array::make(4095, b'a')
  body.push(b'\r')
  body.push(b'\n')
  let output = accepted.feed(Bytes::from_array(body))
  assert_eq(output.length(), 1)
  assert_line(output[0], Bytes::from_array(Array::make(4095, b'a')))

  let lf = Lines::new(lf_only=true)
  let lf_accepted_body : Array[Byte] = Array::make(4095, b'l')
  lf_accepted_body.push(b'\n')
  let lf_accepted_output = lf.feed(Bytes::from_array(lf_accepted_body))
  assert_eq(lf_accepted_output.length(), 1)
  assert_line(lf_accepted_output[0], Bytes::from_array(Array::make(4095, b'l')))

  let lf = Lines::new(lf_only=true)
  let lf_body : Array[Byte] = Array::make(4096, b'l')
  lf_body.push(b'\n')
  let lf_output = lf.feed(Bytes::from_array(lf_body))
  assert_eq(lf_output.length(), 1)
  match lf_output[0] {
    TooLong => ()
    Line(_) => fail("expected TooLong")
  }

  let lines = Lines::new(lf_only=true)
  let oversized : Array[Byte] = Array::make(4095, b'x')
  oversized.push(b'\r')
  oversized.push(b'y')
  oversized.push(b'\n')
  let too_long = lines.feed(Bytes::from_array(oversized))
  assert_eq(too_long.length(), 1)
  match too_long[0] {
    TooLong => ()
    Line(_) => fail("expected TooLong")
  }
  let recovered = lines.feed(b"ok\n")
  assert_eq(recovered.length(), 1)
  assert_line(recovered[0], b"ok")

  let eof_oversized = Lines::new(lf_only=true)
  let eof_body : Array[Byte] = Array::make(4096, b'e')
  let _ = eof_oversized.feed(Bytes::from_array(eof_body))
  let eof_output = eof_oversized.finish()
  assert_eq(eof_output.length(), 1)
  match eof_output[0] {
    TooLong => ()
    Line(_) => fail("expected EOF TooLong")
  }
  assert_eq(eof_oversized.finish().length(), 0)
}

///|
test "LF-only mode handles EOF CR and empty stream" {
  let only_cr = Lines::new(lf_only=true)
  assert_eq(only_cr.feed(b"\r").length(), 0)
  let empty = only_cr.finish()
  assert_eq(empty.length(), 1)
  assert_line(empty[0], b"")

  let final_cr = Lines::new(lf_only=true)
  let _ = final_cr.feed(b"tail\r")
  let output = final_cr.finish()
  assert_eq(output.length(), 1)
  assert_line(output[0], b"tail")

  let after_line = Lines::new(lf_only=true)
  let _ = after_line.feed(b"x\n\r")
  let after_line_output = after_line.finish()
  assert_eq(after_line_output.length(), 1)
  assert_line(after_line_output[0], b"")
  assert_eq(after_line.finish().length(), 0)

  let no_input = Lines::new(lf_only=true)
  assert_eq(no_input.finish().length(), 0)
}
