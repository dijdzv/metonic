///|
test "converted composition displays an end caret while input retains its cursor" {
  assert_eq(display_cursor("日本語", 0, b"\x01\x01\x02"), 3)
  assert_eq(display_cursor("日本語", 1, b"\x02\x03\x03"), 3)
  assert_eq(display_cursor("にほん", 0, b"\x00\x00\x00"), 0)
  assert_eq(display_cursor("にほん", 1, b"\x00\x00\x00"), 1)
  assert_eq(display_cursor("にほん", 3, b"\x00\x00\x00"), 3)
}

///|
test "mixed clauses retain cursors adjacent to unconverted input" {
  assert_eq(display_cursor("にほん語", 3, b"\x00\x00\x00\x01"), 3)
  assert_eq(display_cursor("日本ご", 2, b"\x01\x01\x00"), 2)
  assert_eq(display_cursor("日本ご", 0, b"\x01\x01\x00"), 3)
}

///|
test "attribute-only conversion and reset change presentation without changing input position" {
  assert_eq(display_cursor("あい", 0, b"\x00\x00"), 0)
  assert_eq(display_cursor("あい", 0, b"\x01\x01"), 2)
  assert_eq(display_cursor("あい", 0, b"\x00\x00"), 0)
}

///|
test "unusable attributes preserve valid positions and invalid positions never split UTF-16" {
  assert_eq(display_cursor("日本", 0, b""), 0)
  assert_eq(display_cursor("日本", 1, b"\x01"), 1)
  assert_eq(display_cursor("日本", 0, b"\xFF\x01"), 0)
  assert_eq(display_cursor("😀あ", 0, b"\x01\x00\x01"), 0)
  assert_eq(display_cursor("😀あ", 1, b"\x00\x00\x00"), 3)
  assert_eq(display_cursor("😀あ", 2, b"\x00\x00\x01"), 2)
  assert_eq(display_cursor("😀あ", 0, b"\x01\x01\x01"), 3)
  assert_eq(display_cursor("あ", -1, b""), 1)
  assert_eq(display_cursor("あ", 9, b""), 1)
  assert_eq(display_cursor("", 0, b""), 0)
}

///|
test "ordinary preedit is not a conversion target" {
  assert_eq(target_ranges("あい", b"\x00\x00"), [])
  assert_eq(target_ranges("愛", b"\x02"), [])
}

///|
test "only target clauses are highlighted" {
  assert_eq(target_ranges("日本語", b"\x02\x01\x01"), [(1, 3)])
  assert_eq(target_ranges("日本語", b"\x03\x03\x02"), [(0, 2)])
  assert_eq(target_ranges("日本語", b"\x01\x02\x03"), [(0, 1), (2, 3)])
}

///|
test "missing stale and cleared attributes do not fabricate selection" {
  assert_eq(target_ranges("日本", b""), [])
  assert_eq(target_ranges("日本", b"\x01"), [])
  assert_eq(target_ranges("日", b"\x01\x01"), [])
  assert_eq(target_ranges("", b""), [])
}

///|
test "conversion target cannot split a supplementary character" {
  assert_eq(target_ranges("😀あ", b"\x01\x01\x00"), [(0, 2)])
  assert_eq(target_ranges("😀あ", b"\x01\x00\x00"), [])
  assert_eq(target_ranges("😀あ", b"\x00\x01\x00"), [])
}
