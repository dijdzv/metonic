///|
test "clipping crops original pixels and excludes fully hidden layers" {
  let bounds : @view.Bounds = { x: 10, y: -1, width: 3, height: 2, }
  let source = Bytes::makei(24, i => (i + 1).to_byte())
  let layer : Layer = { bounds, pixels: source, }
  let result = clip_layer(layer, Some({ x: 11, y: 0, width: 2, height: 4, }))
  assert_eq(result.bounds, { x: 11, y: 0, width: 2, height: 1, })
  for i in 0..<8 {
    assert_eq(result.pixels[i], source[i + 16])
  }
  assert_eq(source[0], b'\x01')
  let invisible = clip_layer(
    layer,
    Some({ x: 100, y: 100, width: 20, height: 20, }),
  )
  assert_eq(invisible.pixels, b"")
  assert_eq(invisible.bounds.width, 0)
  assert_eq(clip_layer(layer, None).pixels, source)
  assert_eq(clip_layer(layer, Some(bounds)).pixels, source)
}

///|
test "hit testing rejects hidden pixels and excludes the right and bottom edge" {
  let control = item(
    {
      bounds: { x: 10, y: 20, width: 40, height: 40, },
      text: "",
      reference: None,
      focused: false,
    },
    clip=Some({ x: 20, y: 30, width: 10, height: 10, }),
  )
  assert_false(control.contains(19, 35))
  assert_true(control.contains(20, 30))
  assert_true(control.contains(29, 39))
  assert_false(control.contains(30, 35))
  assert_false(control.contains(25, 40))
}

///|
test "control pixels retain border, label and blank interior" {
  let bounds : @view.Bounds = { x: 0, y: 0, width: 24, height: 40, }
  let label = Bytes::make(8 * 32 * 4, b'\x80')
  let pixels = control_pixels(bounds, label, 4, false)
  assert_eq(pixels.length(), 24 * 40 * 4)
  assert_eq(pixels[0:4], b"\x35\x50\x6d\xff")
  assert_eq(
    pixels[(3 * 24 + 12) * 4:(3 * 24 + 12) * 4 + 4],
    b"\xff\xff\xff\xff",
  )
  assert_eq(
    pixels[(4 * 24 + 12) * 4:(4 * 24 + 12) * 4 + 4],
    b"\x80\x80\x80\x80",
  )
  assert_eq(
    pixels[(37 * 24 + 12) * 4:(37 * 24 + 12) * 4 + 4],
    b"\xff\xff\xff\xff",
  )
  let focused = control_pixels(bounds, label, 4, true)
  assert_eq(focused[0:4], b"\xf5\xa1\x5c\xff")
}

///|
test "checkbox paints checked mark separately from its label and state border" {
  let bounds : @view.Bounds = { x: 0, y: 0, width: 140, height: 40, }
  let label = Bytes::make(96 * 32 * 4, b'\x80')
  let unchecked = checkbox_pixels(bounds, label, 4, false, false, true, false)
  let checked = checkbox_pixels(bounds, label, 4, false, true, true, false)
  let mark = (22 * 140 + 15) * 4
  assert_eq(unchecked[mark:mark + 4], b"\xff\xff\xff\xff")
  assert_eq(checked[mark:mark + 4], b"\x35\x50\x6d\xff")
  assert_eq(
    checked[(4 * 140 + 36) * 4:(4 * 140 + 36) * 4 + 4],
    b"\x80\x80\x80\x80",
  )
  let invalid = checkbox_pixels(bounds, label, 4, false, true, true, true)
  assert_eq(invalid[0:4], b"\xc4\x3c\x3c\xff")
  let disabled = checkbox_pixels(bounds, label, 4, false, true, false, false)
  assert_eq(disabled[0:4], b"\x8a\x8a\x8a\xff")
}
