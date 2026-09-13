///|
test "packed length rejects overflow before allocation" {
  assert_eq(byte_length(-1), None)
  assert_eq(byte_length(0), Some(0))
  assert_eq(byte_length(1073741823), Some(2147483646))
  assert_eq(byte_length(1073741824), None)
}

///|
test "binary code units preserve every byte and independent copies" {
  let source = Bytes::makei(65536 * 2, i => {
    (if i % 2 == 0 { i / 2 } else { i / 512 }).to_byte()
  })
  let packed = source.to_unchecked_string()
  let first = unpack(packed)
  let second = unpack(packed)
  assert_eq(first.length(), source.length())
  for i = 0; i < first.length(); i = i + 1 {
    assert_eq(first[i], source[i])
    first[i] = 0
    assert_eq(second[i], source[i])
  }
  assert_eq(unpack("").length(), 0)
}
