///|
fn verify_vertical_layout(engine : @raster.Engine) -> Unit raise {
  let text = "あいう\nえ\nおかき"
  ignore(@raster.render(engine, text, 300, 96))
  let (middle, x) = @raster.vertical_position(engine, text, 2, true, None).unwrap()
  assert_eq(middle, 5)
  let (last, next_x) = @raster.vertical_position(engine, text, middle, true, x).unwrap()
  assert_eq(last, 8)
  assert_eq(next_x, x)
  assert_true(
    @raster.vertical_position(engine, text, last, true, next_x) is None,
  )
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
  assert_true(
    @raster.vertical_caret(engine, wrapped, line2, true, x2, after=after2)
    is None,
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
  assert_true(@raster.vertical_position(engine, "", 0, false, None) is None)
  stage("vertical caret uses visual lines, sticky x and UTF-16 boundaries")
  let four_lines = "あ\nい\nう\nえ"
  let pixels = @raster.render(
    engine,
    four_lines,
    300,
    96,
    caret=Some(7),
    follow_caret=Some(7),
  )
  assert_eq(@raster.vertical_scroll(engine), 32)
  assert_eq(@raster.caret_position(engine, 7).unwrap().1, 96)
  assert_eq(
    @raster.hit(engine, 0, 64 + @raster.vertical_scroll(engine)),
    Some(6),
  )
  let expected = @raster.render(engine, "い\nう\nえ", 300, 96, caret=Some(5))
  assert_eq(pixels, expected)
  ignore(
    @raster.render(
      engine,
      four_lines,
      300,
      96,
      vertical_scroll=32,
      follow_caret=Some(0),
    ),
  )
  assert_eq(@raster.vertical_scroll(engine), 0)
  ignore(@raster.render(engine, "あ", 300, 96, vertical_scroll=32))
  assert_eq(@raster.vertical_scroll(engine), 0)
  stage(
    "multiline viewport follows the fourth line and returns after navigation or deletion",
  )
  let wrapped_selection = @raster.render(
    engine,
    "あいうえおかきく",
    48,
    96,
    selection=(0, 8),
    follow_caret=Some(8),
  )
  assert_eq(@raster.vertical_scroll(engine), 32)
  let visible_selection = @raster.render(
    engine,
    "うえおかきく",
    48,
    96,
    selection=(0, 6),
  )
  assert_eq(wrapped_selection, visible_selection)
  ignore(
    @raster.render(
      engine,
      "あいうえおかきく",
      96,
      96,
      vertical_scroll=32,
      follow_caret=Some(8),
    ),
  )
  assert_eq(@raster.vertical_scroll(engine), 0)
  ignore(@raster.render(engine, four_lines, 300, 64, follow_caret=Some(7)))
  assert_eq(@raster.vertical_scroll(engine), 64)
  let empty_last = "あ\nい\nう\n"
  let empty_pixels = @raster.render(
    engine,
    empty_last,
    300,
    96,
    caret=Some(empty_last.length()),
    follow_caret=Some(empty_last.length()),
  )
  assert_eq(@raster.caret_position(engine, empty_last.length()), Some((0, 96)))
  assert_eq(@raster.vertical_scroll(engine), 32)
  for y in 64..<96 {
    assert_eq(empty_pixels[y * 300 * 4], b'\x00')
  }
  stage(
    "wrapped selection follows its active end and resize clamps the viewport",
  )
}
