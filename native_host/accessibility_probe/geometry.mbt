///|
#borrow(output)
extern "C" fn range_bounds(range : UInt64, output : FixedArray[UInt64]) -> Int = "TextRange_GetBoundingRectangles"

///|
extern "C" fn array_destroy(array : UInt64) -> Int = "SafeArrayDestroy"

///|
#borrow(output)
extern "C" fn array_upper(
  array : UInt64,
  dimension : UInt,
  output : FixedArray[Int],
) -> Int = "SafeArrayGetUBound"

///|
async fn verify_geometry(
  editor : UInt64,
  value_provider : UInt64,
  hwnd : UInt64,
) -> Unit {
  let engine = @raster.create(
    @fs.read_file(".work/text-assets/NotoSansJP.ttf").binary(),
  ).unwrap()
  for
    sample in [
      ("日本 ABC", 0, 1),
      ("日本 ABC", 3, 4),
      ("ABC 123", 4, 5),
      ("A😀日", 1, 3),
      ("一行目\r\n日本 ABC", 6, 7),
      (String::from_array(Array::make(80, '日')), 40, 41),
    ] {
    verify_character_geometry(
      editor,
      value_provider,
      hwnd,
      engine,
      sample.0,
      sample.1,
      sample.2,
    )
  }
  verify_character_geometry(
    editor,
    value_provider,
    hwnd,
    engine,
    "日本 ABC",
    1,
    1,
    visible=false,
  )
  verify_character_geometry(
    editor,
    value_provider,
    hwnd,
    engine,
    String::from_array(Array::make(80, '日')),
    79,
    80,
    visible=false,
  )
  stage(
    "UIA Japanese, Latin, digit and wrapped rectangles match client origin and raster caret",
  )
}

///|
async fn verify_character_geometry(
  editor : UInt64,
  value_provider : UInt64,
  hwnd : UInt64,
  engine : @raster.Engine,
  text : String,
  start_offset : Int,
  end_offset : Int,
  visible? : Bool = true,
) -> Unit {
  assert_eq(set_value(value_provider, utf16z(text)), 0)
  expect_text(editor, text)
  let provider = FixedArray::make(1, 0UL)
  assert_eq(pattern(editor, 10014, provider), 0)
  defer ignore(release_pattern(provider[0]))
  let range = FixedArray::make(1, 0UL)
  assert_eq(document_range(provider[0], range), 0)
  defer ignore(release_range(range[0]))
  let moved = FixedArray::make(1, 0)
  let units = @accessibility.text_units(text).unwrap()
  let start_index = units.character_at(start_offset).unwrap()
  let end_move = units.character_at(end_offset).unwrap() -
    units.lengths.length()
  assert_eq(move_endpoint(range[0], 0, 0, start_index, moved), 0)
  assert_eq(moved[0], start_index)
  assert_eq(move_endpoint(range[0], 1, 0, end_move, moved), 0)
  assert_eq(moved[0], end_move)
  assert_true(range_matches(range[0], text[start_offset:end_offset].to_owned()))
  let rectangles = FixedArray::make(1, 0UL)
  assert_eq(range_bounds(range[0], rectangles), 0)
  if !visible && rectangles[0] == 0UL {
    return
  }
  assert_true(rectangles[0] != 0UL)
  defer ignore(array_destroy(rectangles[0]))
  let upper = FixedArray::make(1, 0)
  assert_eq(array_upper(rectangles[0], 1U, upper), 0)
  if !visible {
    stage("offscreen text range coordinate count=" + (upper[0] + 1).to_string())
    assert_eq(upper[0], -1)
    return
  }
  assert_eq(upper[0], 3)
  let numbers : Array[Double] = []
  for index in 0..<4 {
    let number = FixedArray::make(1, 0.0)
    assert_eq(
      array_number(rectangles[0], FixedArray::make(1, index), number),
      0,
    )
    numbers.push(number[0])
  }
  let origin = FixedArray::make(2, 0)
  assert_true(client_origin(hwnd, origin) != 0)
  let client = FixedArray::make(4, 0)
  assert_true(client_rect(hwnd, client) != 0)
  ignore(@raster.render(engine, text, (client[2] - 16).max(1).min(640), 96))
  let (start, top) = @raster.caret_position(engine, start_offset).unwrap()
  let (end, _) = @raster.caret_position(engine, end_offset).unwrap()
  // The existing raster caret API truncates fractional advances to integers.
  assert_true((numbers[0] - (origin[0] + 8 + start).to_double()).abs() < 1.01)
  assert_eq(numbers[1], (origin[1] + 8 + top).to_double())
  assert_true(
    numbers[2] > 0 && (numbers[2] - (end - start).to_double()).abs() < 1.01,
  )
  assert_eq(numbers[3], 32.0)
  assert_eq(set_value(value_provider, utf16z("replacement")), 0)
  expect_text(editor, "replacement")
  let stale = FixedArray::make(1, 0UL)
  let status = range_bounds(range[0], stale)
  if stale[0] != 0UL {
    ignore(array_destroy(stale[0]))
  }
  assert_true(status < 0, msg="replaced text range returned stale geometry")
}
