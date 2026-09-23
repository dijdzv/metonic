///|
test "grayscale and selection tint retain their RGBA pixels" {
  assert_eq(
    pack_rgba([0, 127, 255, 255], [false, true, false, true]),
    b"\x00\x00\x00\xff\x59\x68\x7f\xff\xff\xff\xff\xff\xb4\xd2\xff\xff",
  )
}
