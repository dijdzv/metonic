///|
test "capture exclusion does not block ordinary requests or reopen a closed session" {
  let state = new_session_policy()
  assert_eq(begin_session_capture(state), "")
  assert_eq(
    begin_session_capture(state),
    "native session capture already in progress",
  )
  assert_eq(session_admission_error(state), "")
  finish_session_capture(state)
  assert_eq(begin_session_capture(state), "")
  close_session_policy(state)
  finish_session_capture(state)
  assert_eq(begin_session_capture(state), "native session is closed")
}

///|
test "last request ID is valid and exhaustion cannot wrap" {
  let state = new_session_policy()
  state.next_id = 2147483647L
  assert_eq(allocate_session_id(state), 2147483647)
  assert_eq(allocate_session_id(state), 0)
  assert_eq(allocate_session_id(state), 0)
}

///|
test "out of order responses release capacity and duplicates are rejected" {
  let state = new_session_policy()
  for _ in 0..<16 {
    track_session_request(state, allocate_session_id(state))
  }
  assert_eq(
    session_admission_error(state),
    "native session pending limit exceeded",
  )
  assert_true(consume_session_response(state, 16))
  assert_eq(session_admission_error(state), "")
  assert_false(consume_session_response(state, 16))
  assert_false(consume_session_response(state, 4294967297))
  assert_false(consume_session_response(state, 1.5))
  assert_true(consume_session_response(state, 1))
  close_session_policy(state)
  assert_eq(session_admission_error(state), "native session is closed")
  assert_false(consume_session_response(state, 2))
}

///|
test "attachment identity is established once and invalid changes do not replace it" {
  let state = new_session_policy()
  assert_false(accept_attachment_identity(state, "{}"))
  assert_false(accept_attachment_identity(state, "{\"session_id\":\"\"}"))
  assert_true(accept_attachment_identity(state, "{\"session_id\":\"first\"}"))
  assert_false(accept_attachment_identity(state, "{\"session_id\":\"second\"}"))
  assert_true(accept_attachment_identity(state, "{\"session_id\":\"first\"}"))
}
