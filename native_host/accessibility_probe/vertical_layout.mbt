///|
fn verify_vertical_layout(engine : @raster.Engine) -> Unit raise {
  let text = "あいう\nえ\nおかき"
  ignore(@raster.render(engine, text, 300, 96))
  let (middle, x) = @raster.vertical_position(engine, text, 2, true, None).unwrap()
  assert_eq(middle, 5)
  let (last, next_x) = @raster.vertical_position(engine, text, middle, true, x).unwrap()
  assert_eq(last, 8)
  assert_eq(next_x, x)
  let (back, _) = @raster.vertical_position(engine, text, last, false, x).unwrap()
  assert_eq(back, middle)
  assert_true(
    @raster.vertical_position(engine, text + "changed", 2, true, None) is None,
  )
  let empty_lines = "\n\nあ"
  ignore(@raster.render(engine, empty_lines, 300, 96))
  let (line1, x) = @raster.vertical_position(engine, empty_lines, 0, true, None).unwrap()
  assert_eq(line1, 1)
  assert_eq(
    @raster.vertical_position(engine, empty_lines, line1, true, x).unwrap().0,
    2,
  )
  assert_true(
    @raster.vertical_position(engine, empty_lines, 0, false, None) is None,
  )
  let wrapped = "あいうえおか"
  ignore(@raster.render(engine, wrapped, 48, 96))
  let (line1, after, x) = @raster.vertical_caret(engine, wrapped, 0, true, None).unwrap()
  assert_eq(line1, 2)
  assert_true(after)
  assert_eq(@raster.caret_position(engine, line1, after~).unwrap(), (0, 32))
  let (line2, after2, x2) = @raster.vertical_caret(
    engine,
    wrapped,
    line1,
    true,
    x,
    after~,
  ).unwrap()
  assert_eq(line2, 4)
  assert_eq(x2, x)
  assert_eq(
    @raster.caret_position(engine, line2, after=after2).unwrap(),
    (0, 64),
  )
  let (back, back_after, _) = @raster.vertical_caret(
    engine,
    wrapped,
    line2,
    false,
    x2,
    after=after2,
  ).unwrap()
  assert_eq(back, line1)
  assert_eq(
    @raster.caret_position(engine, back, after=back_after).unwrap(),
    (0, 32),
  )
  let supplementary = "😀\nあ"
  ignore(@raster.render(engine, supplementary, 300, 96))
  assert_true(
    @raster.vertical_position(engine, supplementary, 1, true, None) is None,
  )
  assert_eq(
    @raster.vertical_position(engine, supplementary, 0, true, None).unwrap().0,
    3,
  )
  ignore(@raster.render(engine, "", 300, 96))
  assert_true(@raster.vertical_position(engine, "", 0, true, None) is None)
  stage("vertical caret uses visual lines, sticky x and UTF-16 boundaries")
}
