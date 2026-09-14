///|
test "semantic wait transport deadline leaves response time without extending ordinary requests" {
  assert_eq(
    window_request_timeout(
      "{\"op\":\"wait_semantic\",\"semantic_revision\":0,\"timeout_ms\":60000}",
      5000,
    ),
    61000,
  )
  assert_eq(
    window_request_timeout(
      "{\"op\":\"wait_semantic\",\"semantic_revision\":0,\"timeout_ms\":20}", 5000,
    ),
    5000,
  )
  for
    text in [
      "{", "{}", "{\"op\":\"snapshot\",\"timeout_ms\":60000}", "{\"op\":\"wait_semantic\",\"semantic_revision\":-1,\"timeout_ms\":60000}",
      "{\"op\":\"wait_semantic\",\"semantic_revision\":0,\"timeout_ms\":60001}",
      "{\"op\":\"wait_semantic\",\"semantic_revision\":0,\"timeout_ms\":1.5}",
    ] {
    assert_eq(window_request_timeout(text, 5000), 5000)
  }
}

///|
test "display wait preserves its deadline only for a valid scoped frame" {
  for id in ["1", "9223372036854775807"] {
    let request : Json = {
      "op": "wait_display",
      "frame_id": id,
      "frame_scope": "app",
      "timeout_ms": 60000,
    }
    assert_eq(window_request_timeout(request.stringify(), 5000), 61000)
  }
  for id in ["0", "-1", "9223372036854775808", "abc"] {
    let request : Json = {
      "op": "wait_display",
      "frame_id": id,
      "frame_scope": "app",
      "timeout_ms": 60000,
    }
    assert_eq(window_request_timeout(request.stringify(), 5000), 5000)
  }
  let missing_scope : Json = {
    "op": "wait_display",
    "frame_id": "1",
    "timeout_ms": 60000,
  }
  assert_eq(window_request_timeout(missing_scope.stringify(), 5000), 5000)
}

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
