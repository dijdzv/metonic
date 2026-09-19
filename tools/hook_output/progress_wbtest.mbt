///|
test "progress reports completed checks once across arbitrary chunks" {
  let progress = Progress::new()
  assert_eq(progress.feed(b"compiler chatter\nHOOK_CHECK_").length(), 0)
  let messages = progress.feed(
    b"OK: fmt\r\nHOOK_CHECK_OK: check --target wasm\n",
  )
  assert_eq(messages, [
    "checks completed: 1 | fmt", "checks completed: 2 | check --target wasm",
  ])
  assert_eq(progress.feed(b"failure detail\n").length(), 0)
}

///|
test "progress ignores huge lines and bounds labels without losing following milestones" {
  let progress = Progress::new()
  assert_eq(progress.feed(Bytes::make(100000, b'x')).length(), 0)
  assert_eq(progress.line.length(), 8192)
  assert_eq(progress.feed(b"HOOK_CHECK_OK: false\n").length(), 0)
  let label = Array::make(200, "x").join("")
  let messages = progress.feed(@utf8.encode("HOOK_CHECK_OK: " + label + "\n"))
  assert_eq(messages.length(), 1)
  assert_true(messages[0].has_suffix("..."))
  assert_eq(progress.completed, 1)
}
