///|
#borrow(output)
extern "C" fn document_range(
  provider : UInt64,
  output : FixedArray[UInt64],
) -> Int = "TextPattern_get_DocumentRange"

///|
#borrow(output)
extern "C" fn range_text(
  range : UInt64,
  maximum : Int,
  output : FixedArray[UInt64],
) -> Int = "TextRange_GetText"

///|
extern "C" fn release_range(range : UInt64) -> Int = "UiaTextRangeRelease"

///|
extern "C" fn free_bstr(value : UInt64) -> Unit = "SysFreeString"

///|
#borrow(moved)
extern "C" fn move_endpoint(
  range : UInt64,
  endpoint : Int,
  unit : Int,
  count : Int,
  moved : FixedArray[Int],
) -> Int = "TextRange_MoveEndpointByUnit"

///|
extern "C" fn select_range(range : UInt64) -> Int = "TextRange_Select"

///|
extern "C" fn selected_range(provider : UInt64) -> UInt64 = "metonic_uia_selected_range"

///|
fn range_matches(range : UInt64, expected : String) -> Bool {
  let text = FixedArray::make(1, 0UL)
  if range_text(range, -1, text) != 0 {
    return false
  }
  defer free_bstr(text[0])
  if bstr_length(text[0]).reinterpret_as_int() != expected.length() {
    return false
  }
  let bytes = FixedArray::make(expected.length() * 2 + 2, b'\x00')
  copy_name(bytes, text[0], (expected.length() * 2).to_uint64())
  bytes == utf16z(expected)
}

///|
async fn expect_selection(provider : UInt64, expected : String) -> Unit {
  for _ in 0..<200 {
    let range = selected_range(provider)
    if range != 0UL {
      let matches = range_matches(range, expected)
      ignore(release_range(range))
      if matches {
        return
      }
    }
    @async.sleep(5)
  }
  fail("published UIA selection did not match")
}

///|
async fn verify_selection(
  editor : UInt64,
  provider_value : UInt64,
  hwnd : UInt64,
) -> Unit {
  for
    text in [
      "日本😀",
      "日本\r\n😀",
      String::from_array(Array::make(80, '日')) + "😀",
    ] {
    verify_selection_case(editor, provider_value, hwnd, text)
  }
}

///|
async fn verify_selection_case(
  editor : UInt64,
  provider_value : UInt64,
  hwnd : UInt64,
  selected_text : String,
) -> Unit {
  let original = "A" + selected_text + "B"
  assert_eq(set_value(provider_value, utf16z(original)), 0)
  expect_text(editor, original)
  verify_document(editor, original)
  let provider = FixedArray::make(1, 0UL)
  assert_eq(pattern(editor, 10014, provider), 0)
  defer ignore(release_pattern(provider[0]))
  let range = FixedArray::make(1, 0UL)
  assert_eq(document_range(provider[0], range), 0)
  defer ignore(release_range(range[0]))
  let moved = FixedArray::make(1, 0)
  assert_eq(move_endpoint(range[0], 0, 0, 1, moved), 0)
  assert_eq(moved[0], 1)
  assert_eq(move_endpoint(range[0], 1, 0, -1, moved), 0)
  assert_eq(moved[0], -1)
  assert_true(range_matches(range[0], selected_text))
  assert_eq(select_range(range[0]), 0)
  expect_selection(provider[0], selected_text)
  assert_true(post(hwnd, 0x0102U, 0x58UL, 0L) != 0)
  expect_text(editor, "AXB")
  expect_selection(provider[0], "")
  assert_true(select_range(range[0]) < 0)
  assert_true(post(hwnd, 0x0102U, 0x59UL, 0L) != 0)
  expect_text(editor, "AXYB")
  println(
    "production flow: UIA range selection replaced Japanese and supplementary text",
  )
}

///|
fn verify_document(editor : UInt64, expected : String) -> Unit raise Error {
  let provider = FixedArray::make(1, 0UL)
  assert_eq(pattern(editor, 10014, provider), 0)
  assert_true(provider[0] != 0UL)
  defer ignore(release_pattern(provider[0]))
  let range = FixedArray::make(1, 0UL)
  assert_eq(document_range(provider[0], range), 0)
  assert_true(range[0] != 0UL)
  defer ignore(release_range(range[0]))
  let text = FixedArray::make(1, 0UL)
  assert_eq(range_text(range[0], -1, text), 0)
  defer free_bstr(text[0])
  assert_eq(bstr_length(text[0]).reinterpret_as_int(), expected.length())
  let bytes = FixedArray::make(expected.length() * 2 + 2, b'\x00')
  copy_name(bytes, text[0], (expected.length() * 2).to_uint64())
  assert_eq(bytes, utf16z(expected))
}
