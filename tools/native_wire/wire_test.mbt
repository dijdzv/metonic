///|
fn[T] did_raise(f : () -> T raise Error) -> Bool {
  try {
    ignore(f())
    false
  } catch {
    _ => true
  }
}

///|
fn[T] must_raise(f : () -> T raise Error) -> Unit raise Error {
  assert_true(did_raise(f))
}

///|
fn must_not_raise(f : () -> Unit raise Error) -> Unit raise Error {
  assert_true(!did_raise(f))
}

///|
test "wire request boundaries" {
  let request = wire_request(
    1,
    "move",
    Json::object({ "x": Json::number(1.0) }),
    false,
  )
  assert_true(request.contains("\"version\":1"))
  must_raise(fn() raise Error {
    wire_request(0, "move", Json::object({}), false)
  })
  must_raise(fn() raise Error {
    wire_request(
      1,
      "move",
      Json::object({ "version": Json::number(2.0) }),
      false,
    )
  })
  must_raise(fn() raise Error {
    wire_request(1, "move", Json::object({ "id": Json::number(2.0) }), false)
  })
  must_raise(fn() raise Error {
    wire_request(
      1,
      "move",
      Json::object({ "op": Json::string("other") }),
      false,
    )
  })
  must_raise(fn() raise Error {
    wire_request(1, "capture", Json::object({}), false)
  })
  must_not_raise(fn() raise Error {
    ignore(wire_request(1, "capture", Json::object({}), true))
  })
  must_raise(fn() raise Error {
    wire_request(1, "move", Json::string("bad"), false)
  })
}

///|
test "wire response schema boundaries" {
  let (id, _) = wire_response(
    b"{\"version\":1,\"id\":7,\"ok\":true,\"state\":[0,0,1,1,0,0,640,360],\"frame\":0}",
  )
  assert_eq(id, 7)
  for
    line in [
      b"{\"version\":2,\"id\":1,\"ok\":true,\"state\":[0,0,1,1,0,0,640,360],\"frame\":0}",
      b"{\"version\":1.5,\"id\":1,\"ok\":true,\"state\":[0,0,1,1,0,0,640,360],\"frame\":0}",
      b"{\"version\":1,\"id\":1.5,\"ok\":true,\"state\":[0,0,1,1,0,0,640,360],\"frame\":0}",
      b"{\"version\":1,\"id\":1,\"ok\":true,\"state\":[0.5,0,1,1,0,0,640,360],\"frame\":0}",
      b"{\"version\":1,\"id\":1,\"ok\":true,\"state\":[0,0,1,1,0,0,0,360],\"frame\":0}",
      b"{\"version\":1,\"id\":1,\"ok\":true,\"state\":[0,0,1,1,0,0,2049,360],\"frame\":0}",
      b"{\"version\":1,\"id\":1,\"ok\":true,\"state\":[0,0,1,1,0,0,640,360],\"frame\":-1}",
      b"{\"version\":1,\"id\":1,\"ok\":true,\"state\":[0,0,1,1,0,0,640,360],\"frame\":0.5}",
    ] {
    must_raise(fn() raise Error { wire_response(line) })
  }
}

///|
test "wire framing boundaries" {
  let lines = WireLines::new()
  let frames = lines.feed(b"one\r\ntwo\n")
  assert_eq(frames.length(), 2)
  assert_eq(frames[0], b"one")
  assert_eq(frames[1], b"two")
  let fragmented = WireLines::new()
  assert_eq(fragmented.feed(b"one\r").length(), 0)
  let fragment_frames = fragmented.feed(b"\ntwo\n")
  assert_eq(fragment_frames.length(), 2)
  assert_eq(fragment_frames[0], b"one")
  assert_eq(fragment_frames[1], b"two")
  must_not_raise(fn() raise Error { fragmented.finish() })
  let clean = WireLines::new()
  must_not_raise(fn() raise Error { clean.finish() })
  let exact = WireLines::new()
  ignore(exact.feed(Bytes::from_array(Array::make(65536, b'a'))))
  must_not_raise(fn() raise Error { ignore(exact.feed(b"\n")) })
  let truncated = WireLines::new()
  ignore(truncated.feed(b"partial"))
  must_raise(fn() raise Error { truncated.finish() })
  must_raise(fn() raise Error {
    WireLines::new().feed(Bytes::from_array(Array::make(65537, b'x')))
  })
  let two_lines = WireLines::new()
  let combined : Array[Byte] = []
  let mut index = 0
  while index < 40000 {
    combined.push(b'z')
    index = index + 1
  }
  combined.push(b'\n')
  index = 0
  while index < 40000 {
    combined.push(b'z')
    index = index + 1
  }
  combined.push(b'\n')
  assert_eq(two_lines.feed(Bytes::from_array(combined)).length(), 2)
}

///|
test "wire utf8 request limit" {
  let one = wire_request(
    1,
    "move",
    Json::object({ "text": Json::string("a") }),
    false,
  )
  let fixed = @utf8.encode(one).length() - 1
  let ascii_count = 4095 - fixed - 3
  let text = "日" + String::from_array(Array::make(ascii_count, 'a'))
  let exact = wire_request(
    1,
    "move",
    Json::object({ "text": Json::string(text) }),
    false,
  )
  assert_eq(@utf8.encode(exact).length(), 4095)
  must_raise(fn() raise Error {
    wire_request(
      1,
      "move",
      Json::object({ "text": Json::string(text + "a") }),
      false,
    )
  })
}

///|
test "must_raise detects normal closure" {
  assert_true(did_raise(fn() raise Error { must_raise(fn() { () }) }))
}
