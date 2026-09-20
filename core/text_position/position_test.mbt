///|
test "mixed unicode prefix positions" {
  let text = "A日本😀e\u{0301}"
  assert_eq(utf16_to_utf8(text, 0), Some(0))
  assert_eq(utf16_to_utf8(text, 1), Some(1))
  assert_eq(utf16_to_utf8(text, 2), Some(4))
  assert_eq(utf16_to_utf8(text, 3), Some(7))
  assert_eq(utf16_to_utf8(text, 5), Some(11))
  assert_eq(utf16_to_utf8(text, 6), Some(12))
  assert_eq(utf16_to_utf8(text, 7), Some(14))
  assert_eq(utf16_to_scalar(text, 0), Some(0))
  assert_eq(utf16_to_scalar(text, 1), Some(1))
  assert_eq(utf16_to_scalar(text, 2), Some(2))
  assert_eq(utf16_to_scalar(text, 3), Some(3))
  assert_eq(utf16_to_scalar(text, 5), Some(4))
  assert_eq(utf16_to_scalar(text, 6), Some(5))
  assert_eq(utf16_to_scalar(text, 7), Some(6))
  assert_eq(utf8_to_utf16(text, 0), Some(0))
  assert_eq(utf8_to_utf16(text, 1), Some(1))
  assert_eq(utf8_to_utf16(text, 4), Some(2))
  assert_eq(utf8_to_utf16(text, 7), Some(3))
  assert_eq(utf8_to_utf16(text, 11), Some(5))
  assert_eq(utf8_to_utf16(text, 12), Some(6))
  assert_eq(utf8_to_utf16(text, 14), Some(7))
  assert_eq(scalar_to_utf16(text, 0), Some(0))
  assert_eq(scalar_to_utf16(text, 1), Some(1))
  assert_eq(scalar_to_utf16(text, 2), Some(2))
  assert_eq(scalar_to_utf16(text, 3), Some(3))
  assert_eq(scalar_to_utf16(text, 4), Some(5))
  assert_eq(scalar_to_utf16(text, 5), Some(6))
  assert_eq(scalar_to_utf16(text, 6), Some(7))
}

///|
test "mixed unicode rejects invalid boundaries" {
  let text = "A日本😀e\u{0301}"
  for offset in [4, 2, 3, 5, 6, 8, 9, 10, 13] {
    if offset == 4 {
      assert_eq(utf16_to_utf8(text, offset), None)
    } else {
      assert_eq(utf8_to_utf16(text, offset), None)
    }
  }
  assert_eq(utf16_to_utf8(text, -1), None)
  assert_eq(utf16_to_utf8(text, 8), None)
  assert_eq(utf16_to_scalar(text, -1), None)
  assert_eq(utf16_to_scalar(text, 4), None)
  assert_eq(utf16_to_scalar(text, 8), None)
  assert_eq(utf8_to_utf16(text, -1), None)
  assert_eq(utf8_to_utf16(text, 15), None)
  assert_eq(scalar_to_utf16(text, -1), None)
  assert_eq(scalar_to_utf16(text, 7), None)
}

///|
test "two byte utf8 boundary" {
  let text = "é"
  assert_eq(utf16_to_utf8(text, 0), Some(0))
  assert_eq(utf16_to_utf8(text, 1), Some(2))
  assert_eq(utf8_to_utf16(text, 0), Some(0))
  assert_eq(utf8_to_utf16(text, 2), Some(1))
  assert_eq(utf8_to_utf16(text, 1), None)
}

///|
test "empty and simple text" {
  assert_eq(utf16_to_utf8("", 0), Some(0))
  assert_eq(utf8_to_utf16("", 0), Some(0))
  assert_eq(utf16_to_scalar("", 0), Some(0))
  assert_eq(scalar_to_utf16("", 0), Some(0))
  assert_eq(utf16_to_utf8("abc", 1), Some(1))
  assert_eq(utf8_to_utf16("abc", 2), Some(2))
  assert_eq(utf16_to_scalar("abc", 3), Some(3))
  assert_eq(scalar_to_utf16("abc", 3), Some(3))
}

///|
test "zwj sequence uses scalar boundaries" {
  let text = "👩\u{200D}💻"
  assert_eq(utf16_to_scalar(text, 0), Some(0))
  assert_eq(utf16_to_scalar(text, 2), Some(1))
  assert_eq(utf16_to_scalar(text, 3), Some(2))
  assert_eq(utf16_to_scalar(text, 5), Some(3))
  assert_eq(utf16_to_utf8(text, 0), Some(0))
  assert_eq(utf16_to_utf8(text, 2), Some(4))
  assert_eq(utf16_to_utf8(text, 3), Some(7))
  assert_eq(utf16_to_utf8(text, 5), Some(11))
  assert_eq(utf8_to_utf16(text, 4), Some(2))
  assert_eq(utf8_to_utf16(text, 7), Some(3))
  assert_eq(utf8_to_utf16(text, 11), Some(5))
}

///|
test "unpaired utf16 code units are rejected" {
  let high = String::from_array([(0xD800).unsafe_to_char(), 'A'])
  let low = String::from_array([(0xDC00).unsafe_to_char(), 'A'])
  let trailing = String::from_array(['A', (0xD800).unsafe_to_char()])
  for text in [high, low, trailing] {
    assert_eq(utf16_to_utf8(text, 0), None)
    assert_eq(utf8_to_utf16(text, 0), None)
    assert_eq(utf16_to_scalar(text, 0), None)
    assert_eq(scalar_to_utf16(text, 0), None)
  }
}
