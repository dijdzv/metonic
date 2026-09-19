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
