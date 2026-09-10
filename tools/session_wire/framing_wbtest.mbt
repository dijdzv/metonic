///|
test "response lines survive split CRLF, blank chunks and multiple records" {
  let state = new_response_framer()
  assert_eq(state.limit, 32 * 1024 * 1024)
  assert_eq(append_response_text(state, "日本"), [])
  assert_eq(append_response_text(state, ""), [])
  assert_eq(append_response_text(state, "語\r"), [])
  assert_eq(append_response_text(state, "\n\nnext\nlast"), [
    "日本語", "", "next",
  ])
  assert_eq(append_response_text(state, "\n"), ["last"])
  assert_eq(finish_response_framer(state), "")
}

///|
test "response line byte limit counts UTF-8 and includes CR before stripping" {
  let state : ResponseFramer = { parts: [], limit: 8, bytes: 0, error: "", }
  assert_eq(append_response_text(state, "日本a\r\n"), ["日本a"])
  assert_eq(response_framing_error(state), "")
  assert_eq(append_response_text(state, "日本"), [])
  assert_eq(append_response_text(state, "ab"), [])
  assert_eq(append_response_text(state, "c\n"), [])
  assert_eq(
    response_framing_error(state),
    "native session response line exceeds 32MiB",
  )
  assert_eq(state.bytes, 0)
  assert_eq(state.parts.length(), 0)
  assert_eq(append_response_text(state, "valid\n"), [])
}

///|
test "completed response precedes an overlong next line in one chunk" {
  let state : ResponseFramer = { parts: [], limit: 4, bytes: 0, error: "", }
  assert_eq(append_response_text(state, "okay\n12345"), ["okay"])
  assert_true(response_framing_error(state) != "")
}

///|
test "EOF rejects a partial line but accepts an empty stream" {
  let empty = new_response_framer()
  assert_eq(finish_response_framer(empty), "")
  let partial = new_response_framer()
  assert_eq(append_response_text(partial, "unfinished\r"), [])
  assert_eq(
    finish_response_framer(partial),
    "truncated native session response line",
  )
  assert_eq(partial.parts.length(), 0)
  assert_eq(append_response_text(partial, "\n"), [])
}

///|
test "clearing pending response fragments releases their byte budget" {
  let state = new_response_framer()
  ignore(append_response_text(state, "discard"))
  clear_response_framer(state)
  assert_eq(append_response_text(state, "new\n"), ["new"])
  assert_eq(finish_response_framer(state), "")
}
