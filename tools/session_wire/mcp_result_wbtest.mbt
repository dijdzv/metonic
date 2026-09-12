///|
test "native MCP preserves session precedence errors and capture content" {
  let state : Json = {
    "session_id": "response-session",
    "ok": false,
    "error": "古い結果",
    "frame": 9007199254740991,
  }
  let image : Json = { "data": "AA==", "mimeType": "" }
  let expected : Json = {
    "isError": true,
    "content": [
      { "type": "text", "text": state.stringify() },
      { "type": "image", "data": "AA==", "mimeType": "image/png" },
    ],
  }
  let actual = @json.parse(
    native_mcp_result("fallback", state.stringify(), image.stringify()),
  )
  let content : Array[Json] = @json.from_json(field(actual, "content"))
  assert_eq(@json.parse(@json.from_json(field(content[0], "text"))), state)
  let expected_content : Array[Json] = @json.from_json(
    field(expected, "content"),
  )
  assert_eq(content[1], expected_content[1])
  assert_eq(field(actual, "isError"), Json::boolean(true))
  assert_eq(content.length(), 2)
}

///|
test "window MCP separates image bytes from state and retains image metadata" {
  let state : Json = {
    "text": "日本語\nabc",
    "frames": 42,
    "image": {
      "data": "AA==",
      "mimeType": "image/png",
      "width": 3,
      "height": 4,
      "frame": 42,
      "source": "offscreen",
    },
  }
  let result = @json.parse(window_mcp_result("session", state.stringify()))
  let content : Array[Json] = @json.from_json(field(result, "content"))
  assert_eq(content.length(), 3)
  assert_eq(
    @json.parse(@json.from_json(field(content[0], "text"))),
    ({ "session_id": "session", "text": "日本語\nabc", "frames": 42 } : Json),
  )
  assert_eq(
    content[1],
    ({ "type": "image", "data": "AA==", "mimeType": "image/png" } : Json),
  )
  assert_eq(
    @json.parse(@json.from_json(field(content[2], "text"))),
    ({ "width": 3, "height": 4, "frame": 42, "source": "offscreen" } : Json),
  )
}

///|
test "native MCP transport failures keep structured session diagnostics" {
  let result = @json.parse(native_mcp_failure("session", "取消\nfailed"))
  let content : Array[Json] = @json.from_json(field(result, "content"))
  assert_eq(field(result, "isError"), Json::boolean(true))
  assert_eq(content.length(), 1)
  assert_eq(
    @json.parse(@json.from_json(field(content[0], "text"))),
    ({ "session_id": "session", "ok": false, "error": "取消\nfailed" } : Json),
  )
}
