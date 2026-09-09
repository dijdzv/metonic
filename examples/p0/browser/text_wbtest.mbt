///|
test "bulk font receive rejects invalid input and clears pending words" {
  assert_eq(font_begin(4), 1)
  assert_eq(font_put(0x01020304), 1)
  assert_eq(font_receive(FixedArray::make(0, b'\x00')), 0)
  assert_eq(font_commit(), 0)
  assert_eq(font_receive(FixedArray::make(4, b'\x00')), 0)
  assert_eq(font_put(0), 0)
  assert_eq(font_commit(), 0)
  assert_eq(font_receive(FixedArray::make(16777217, b'\x00')), 0)
  assert_eq(font_commit(), 0)
  text_dispose()
}

///|
test "layer bytes reject unavailable indices after disposal" {
  text_dispose()
  assert_eq(view_layer_bytes(-1), b"")
  assert_eq(view_layer_bytes(1), b"")
  assert_eq(view_layer_count(), 0)
  assert_eq(view_layer_bytes(0), b"")
}

///|
test "text contract accepts ASCII Japanese surrogate pair and combining mark" {
  text_dispose()
  assert_eq(text_begin(7), 1)
  for unit in [0x41, 0x65E5, 0x672C, 0xD83D, 0xDE00, 0x65, 0x301] {
    assert_eq(text_put(unit), 1)
  }
  assert_eq(decode_text(), Some("A日本😀e\u{0301}"))
  assert_eq(text_commit(96), 0)
}

///|
test "text contract rejects unpaired surrogate sequences" {
  text_dispose()
  assert_eq(text_begin(1), 1)
  assert_eq(text_put(0xD83D), 1)
  assert_eq(decode_text(), None)
  assert_eq(text_commit(96), 0)
  assert_eq(text_begin(2), 1)
  assert_eq(text_put(0xD83D), 1)
  assert_eq(text_put(0x41), 1)
  assert_eq(decode_text(), None)
  assert_eq(text_commit(96), 0)
  assert_eq(text_begin(1), 1)
  assert_eq(text_put(0xDE00), 1)
  assert_eq(decode_text(), None)
  assert_eq(text_commit(96), 0)
}

///|
test "text contract bounds and pending writes" {
  text_dispose()
  assert_eq(text_begin(-1), 0)
  assert_eq(text_begin(1025), 0)
  assert_eq(text_put(65), 0)
  assert_eq(text_begin(1), 1)
  assert_eq(text_put(65), 1)
  assert_eq(text_put(66), 0)
  assert_eq(text_commit(96), 0)
  assert_eq(text_commit(96), 0)
}

///|
test "font contract clears invalid pending input and dispose" {
  text_dispose()
  assert_eq(font_begin(0), 0)
  assert_eq(font_put(0), 0)
  assert_eq(font_begin(4), 1)
  assert_eq(font_put(0x01020304), 1)
  assert_eq(font_commit(), 0)
  assert_eq(font_commit(), 0)
  assert_eq(text_width(), 0)
  text_dispose()
  assert_eq(text_width(), 0)
  assert_eq(text_pixel(0), -1)
}
