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
