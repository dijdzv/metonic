///|
async fn verify_text_layout() -> Unit {
  let units = @accessibility.text_units("A日😀\r\nB").unwrap()
  assert_eq(units.offsets, [0, 1, 2, 4, 6, 7])
  assert_eq(units.lengths, b"\x01\x03\x04\x02\x01")
  assert_eq(units.character_at(3), None)
  assert_eq(units.character_at(5), None)
  assert_eq(units.character_at(7), Some(5))
  assert_eq(units.utf16_at(3), Some(4))
  assert_eq(units.utf16_at(-1), None)
  assert_eq(units.utf16_at(6), None)
  let empty = @accessibility.text_units("").unwrap()
  assert_eq(empty.character_at(0), Some(0))
  assert_eq(empty.lengths.length(), 0)
  let engine = @raster.create(
    @fs.read_file(".work/text-assets/NotoSansJP.ttf").binary(),
  ).unwrap()
  for
    text in [
      "", "日本語 ABC 😀", "first\nsecond\nthird\nfourth", "a\n", "\n\n", "one\r\ntwo\r\n",
    ] {
    ignore(@raster.render(engine, text, 64, 32))
    let runs = @raster.text_runs(engine, text).unwrap()
    assert_eq(runs[0].start, 0)
    assert_eq(runs[runs.length() - 1].end, text.length())
    if text.has_suffix("\n") {
      assert_eq(runs[runs.length() - 1].start, text.length())
    }
    if text == "first\nsecond\nthird\nfourth" {
      assert_true(runs[runs.length() - 1].top >= 96.0F)
    }
    assert_true(@raster.text_runs(engine, text + "changed") is None)
  }
  stage(
    "retained text layout covers empty, wrapped, offscreen and trailing lines",
  )
}
