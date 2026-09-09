///|
test "request envelopes validate protocol shape and reserved identifiers" {
  for
    text in [
      "null", "[]", "{", "{}", "{\"id\":0,\"op\":\"snapshot\",\"args\":{}}", "{\"id\":1.5,\"op\":\"snapshot\",\"args\":{}}",
      "{\"id\":2147483648,\"op\":\"snapshot\",\"args\":{}}", "{\"id\":1,\"op\":null,\"args\":{}}",
    ] {
    assert_eq(
      validate_request(text, false, 1, "snapshot"),
      "invalid native session request",
    )
    assert_eq(
      validate_request(text, true, 1, "snapshot"),
      "invalid native session request",
    )
  }
  assert_eq(
    validate_request(
      "{\"id\":1,\"op\":\"snapshot\",\"args\":{}}", false, 1, "snapshot",
    ),
    "",
  )
  assert_eq(
    validate_request(
      "{\"id\":2147483647,\"op\":\"snapshot\"}", true, 2147483647, "snapshot",
    ),
    "",
  )
  for args in ["null", "[]", "\"string\"", "true"] {
    assert_eq(
      validate_request(
        "{\"id\":1,\"op\":\"echo\",\"args\":" + args + "}",
        false,
        1,
        "echo",
      ),
      "invalid native session request",
    )
  }
}

///|
test "request limit counts UTF-8 bytes rather than characters" {
  for window in [true, false] {
    let prefix = if window {
      "{\"id\":1,\"op\":\"echo\",\"text\":\""
    } else {
      "{\"id\":1,\"op\":\"echo\",\"args\":{\"text\":\""
    }
    let suffix = if window { "\"}" } else { "\"}}" }
    let mut text = prefix + "日本語😀"
    while @utf8.encode(text + suffix).length() < 4095 {
      text = text + "x"
    }
    assert_eq(@utf8.encode(text + suffix).length(), 4095)
    assert_eq(validate_request(text + suffix, window, 1, "echo"), "")
    assert_eq(
      validate_request(text + "x" + suffix, window, 1, "echo"),
      "native session request exceeds 4095 bytes",
    )
  }
}

///|
test "serialization cannot replace a reserved request identity" {
  for window in [true, false] {
    let text = "{\"id\":2,\"op\":\"snapshot\",\"args\":{}}"
    assert_eq(
      validate_request(text, window, 1, "snapshot"),
      "invalid native session request",
    )
    assert_eq(
      validate_request(text, window, 2, "capture"),
      "invalid native session request",
    )
    assert_eq(validate_request(text, window, 2, "snapshot"), "")
  }
}
