///|
extern "C" fn next_window(
  parent : UInt64,
  after : UInt64,
  class_name : UInt64,
  title : UInt64,
) -> UInt64 = "FindWindowExW"

///|
#borrow(pid)
extern "C" fn window_pid(hwnd : UInt64, pid : FixedArray[Int]) -> UInt = "GetWindowThreadProcessId"

///|
extern "C" fn visible(hwnd : UInt64) -> Int = "IsWindowVisible"

///|
extern "C" fn is_window(hwnd : UInt64) -> Int = "IsWindow"

///|
#borrow(text)
extern "C" fn window_title(
  hwnd : UInt64,
  text : FixedArray[Byte],
  capacity : Int,
) -> Int = "GetWindowTextW"

///|
extern "C" fn resize_window(
  hwnd : UInt64,
  after : UInt64,
  x : Int,
  y : Int,
  width : Int,
  height : Int,
  flags : UInt,
) -> Int = "SetWindowPos"

///|
#borrow(rect)
extern "C" fn client_rect(hwnd : UInt64, rect : FixedArray[Int]) -> Int = "GetClientRect"

///|
#borrow(index, output)
extern "C" fn array_number(
  array : UInt64,
  index : FixedArray[Int],
  output : FixedArray[Double],
) -> Int = "SafeArrayGetElement"

///|
extern "C" fn post(
  hwnd : UInt64,
  message : UInt,
  wparam : UInt64,
  lparam : Int64,
) -> Int = "PostMessageW"

///|
extern "C" fn initialize(reserved : UInt64, kind : UInt) -> Int = "CoInitializeEx"

///|
extern "C" fn uninitialize() -> Unit = "CoUninitialize"

///|
extern "C" fn flush(stream : UInt64) -> Int = "fflush"

///|
fn stage(name : String) -> Unit {
  println("production flow: " + name)
  ignore(flush(0UL))
}

///|
#borrow(result)
extern "C" fn node_from_handle(
  hwnd : UInt64,
  result : FixedArray[UInt64],
) -> Int = "UiaNodeFromHandle"

///|
extern "C" fn navigate(node : UInt64, direction : Int) -> UInt64 = "metonic_uia_navigate"

///|
#borrow(result)
extern "C" fn pattern(
  node : UInt64,
  id : Int,
  result : FixedArray[UInt64],
) -> Int = "UiaGetPatternProvider"

///|
extern "C" fn toggle(pattern : UInt64) -> Int = "TogglePattern_Toggle"

///|
extern "C" fn invoke(pattern : UInt64) -> Int = "InvokePattern_Invoke"

///|
extern "C" fn focus_node(node : UInt64) -> Int = "UiaSetFocus"

///|
#borrow(text)
extern "C" fn set_value(pattern : UInt64, text : FixedArray[Byte]) -> Int = "ValuePattern_SetValue"

///|
extern "C" fn release_pattern(pattern : UInt64) -> Int = "UiaPatternRelease"

///|
extern "C" fn release_node(node : UInt64) -> Int = "UiaNodeRelease"

///|
#borrow(value)
extern "C" fn property(
  node : UInt64,
  id : Int,
  value : FixedArray[UInt64],
) -> Int = "UiaGetPropertyValue"

///|
#borrow(value)
extern "C" fn clear(value : FixedArray[UInt64]) -> Int = "VariantClear"

///|
extern "C" fn bstr_length(value : UInt64) -> UInt = "SysStringLen"

///|
#borrow(output)
extern "C" fn copy_name(
  output : FixedArray[Byte],
  pointer : UInt64,
  length : UInt64,
) -> Unit = "RtlMoveMemory"

///|
fn owned_window(pid : Int) -> UInt64 {
  let owner = FixedArray::make(1, 0)
  let mut cursor = 0UL
  for _ in 0..<4096 {
    cursor = next_window(0UL, cursor, 0UL, 0UL)
    if cursor == 0UL {
      return 0UL
    }
    ignore(window_pid(cursor, owner))
    if owner[0] == pid && visible(cursor) != 0 {
      return cursor
    }
  }
  0UL
}

///|
fn text_is(node : UInt64, id : Int, expected : String) -> Bool {
  let value = FixedArray::make(3, 0UL)
  if property(node, id, value) != 0 {
    return false
  }
  defer ignore(clear(value))
  if value[0] != 8UL ||
    bstr_length(value[1]).reinterpret_as_int() != expected.length() {
    return false
  }
  let bytes = FixedArray::make(expected.length() * 2, b'\x00')
  copy_name(bytes, value[1], bytes.length().to_uint64())
  for index in 0..<expected.length() {
    let unit = expected[index].to_int()
    if bytes[index * 2].to_int() != (unit & 255) ||
      bytes[index * 2 + 1].to_int() != unit >> 8 {
      return false
    }
  }
  true
}

///|
fn integer(node : UInt64, id : Int) -> Int {
  let value = FixedArray::make(3, 0UL)
  if property(node, id, value) != 0 {
    return -1
  }
  defer ignore(clear(value))
  if value[0] == 3UL {
    value[1].to_int()
  } else {
    -1
  }
}

///|
fn utf16z(text : String) -> FixedArray[Byte] {
  let bytes = FixedArray::make(text.length() * 2 + 2, b'\x00')
  for index in 0..<text.length() {
    let unit = text[index].to_int()
    bytes[index * 2] = (unit & 255).to_byte()
    bytes[index * 2 + 1] = (unit >> 8).to_byte()
  }
  bytes
}

///|
fn bounds_component(node : UInt64, index : Int) -> Double {
  let value = FixedArray::make(3, 0UL)
  if property(node, 30001, value) != 0 {
    return -1
  }
  defer ignore(clear(value))
  if value[0] != 8197UL {
    return -1
  }
  let output = FixedArray::make(1, 0.0)
  if array_number(value[1], FixedArray::make(1, index), output) != 0 {
    return -1
  }
  output[0]
}

///|
fn bounds_width(node : UInt64) -> Double {
  bounds_component(node, 2)
}

///|
async fn expect_focus(node : UInt64) -> Unit {
  for _ in 0..<200 {
    let value = FixedArray::make(3, 0UL)
    assert_eq(property(node, 30008, value), 0)
    let focused = value[0] == 11UL && (value[1] & 65535UL) != 0UL
    ignore(clear(value))
    if focused {
      return
    }
    @async.sleep(5)
  }
  fail("shared view focus not published")
}

///|
async fn request_action(
  hwnd : UInt64,
  node : UInt64,
  provider : UInt64,
) -> Unit {
  let mode = @env.get_env_var("METONIC_VIEW_ACTION").unwrap_or("invoke")
  let began = uptime_ms()
  match mode {
    "invoke" => assert_eq(invoke(provider), 0)
    "keyboard" => {
      assert_eq(focus_node(node), 0)
      expect_focus(node)
      assert_true(post(hwnd, 0x0100U, 0x28UL, 0L) != 0)
      assert_true(post(hwnd, 0x0100U, 0x0DUL, 0L) != 0)
    }
    "pointer" => {
      let origin = FixedArray::make(2, 0)
      assert_true(client_origin(hwnd, origin) != 0)
      let x = (bounds_component(node, 0) + bounds_component(node, 2) / 2).to_int() -
        origin[0]
      let y = (bounds_component(node, 1) + bounds_component(node, 3) / 2).to_int() -
        origin[1]
      let point = ((y << 16) | x).to_int64()
      assert_true(post(hwnd, 0x0201U, 1UL, point) != 0)
      assert_true(post(hwnd, 0x0202U, 0UL, point) != 0)
    }
    _ => fail("unknown shared view action mode")
  }
  stage(
    "shared request action: " +
    mode +
    " elapsed_ms=" +
    (uptime_ms() - began).to_string(),
  )
}

///|
async fn expect_text(node : UInt64, expected : String) -> Unit {
  for _ in 0..<500 {
    if text_is(node, 30045, expected) {
      return
    }
    @async.sleep(20)
  }
  fail("UIA text update missing")
}

///|
fn child_named(parent : UInt64, name : String) -> UInt64 {
  let mut node = navigate(parent, 3)
  for _ in 0..<16 {
    if node == 0UL {
      return 0UL
    }
    if text_is(node, 30005, name) {
      return node
    }
    let next = navigate(node, 1)
    ignore(release_node(node))
    node = next
  }
  if node != 0UL {
    ignore(release_node(node))
  }
  0UL
}

///|
async fn main {
  @async.with_timeout(60000, async fn() {
    verify_text_layout()
    guard initialize(0UL, 0U) >= 0 else {
      fail("UIA COM initialization failed")
    }
    defer uninitialize()
    let pid = @string.parse_int(@env.args()[1][:])
    let mut hwnd = 0UL
    while hwnd == 0UL {
      hwnd = owned_window(pid)
      @async.sleep(20)
    }
    if @env.args().length() == 3 && @env.args()[2] == "close-only" {
      guard post(hwnd, 0x0010U, 0UL, 0L) != 0 else {
        fail("owned window close request failed")
      }
      for _ in 0..<500 {
        if is_window(hwnd) == 0 {
          println("OWNED_WINDOW_CLOSE_OK")
          return
        }
        @async.sleep(20)
      }
      fail("owned window did not close")
    }
    let root = FixedArray::make(1, 0UL)
    let title = FixedArray::make(16, b'\x00')
    guard window_title(hwnd, title, 8) == 7 && title == utf16z("Metonic") else {
      fail("native title differs from application name")
    }
    guard node_from_handle(hwnd, root) == 0 && root[0] != 0UL else {
      fail("production UIA root missing")
    }
    defer ignore(release_node(root[0]))
    stage("window attached")
    guard text_is(root[0], 30005, "Metonic") else {
      fail("production UIA root name mismatch")
    }
    let button = child_named(root[0], "Toggle")
    guard button != 0UL else { fail("production UIA button missing") }
    defer ignore(release_node(button))
    guard text_is(button, 30005, "Toggle") && integer(button, 30003) == 50000 else {
      fail("production button role/name mismatch")
    }
    let editor = child_named(root[0], "Text")
    guard editor != 0UL else { fail("production UIA editor missing") }
    defer ignore(release_node(editor))
    guard text_is(editor, 30005, "Text") && integer(editor, 30003) == 50004 else {
      fail("production editor role/name mismatch")
    }
    for _ in 0..<500 {
      if text_is(editor, 30045, "日本語の描画を確認します ABC 123") {
        break
      }
      @async.sleep(20)
    }
    guard text_is(editor, 30045, "日本語の描画を確認します ABC 123") else {
      fail("production shared editor value mismatch")
    }
    guard integer(button, 30086) == 0 else {
      fail("production initial toggle mismatch")
    }
    capture_presentation(hwnd, "initial")
    let provider = FixedArray::make(1, 0UL)
    guard pattern(button, 10015, provider) == 0 && provider[0] != 0UL else {
      fail("production Toggle pattern missing")
    }
    defer ignore(release_pattern(provider[0]))
    guard toggle(provider[0]) == 0 else {
      fail("production Toggle action failed")
    }
    for _ in 0..<500 {
      if integer(button, 30086) == 1 {
        break
      }
      @async.sleep(20)
    }
    guard integer(button, 30086) == 1 else {
      fail("UIA action did not change shared state")
    }
    guard text_is(editor, 30045, "日本語の描画を確認します ABC 123") else {
      fail("UIA action changed editor")
    }
    capture_presentation(hwnd, "toggled")
    let value_provider = FixedArray::make(1, 0UL)
    guard pattern(editor, 10002, value_provider) == 0 &&
      value_provider[0] != 0UL else {
      fail("Value pattern missing")
    }
    defer ignore(release_pattern(value_provider[0]))
    let read_only_property = FixedArray::make(3, 0UL)
    guard property(editor, 30046, read_only_property) == 0 else {
      fail("read-only property missing")
    }
    let writable = read_only_property[0] == 11UL &&
      (read_only_property[1] & 65535UL) == 0UL
    ignore(clear(read_only_property))
    guard writable else { fail("production editor remains read-only") }
    verify_selection(editor, value_provider[0], hwnd)
    for
      text in ["日本語 ABC 😀", "変更後 XYZ 123", "", "再入力 🚀"] {
      guard set_value(value_provider[0], utf16z(text)) == 0 else {
        fail("Value request failed")
      }
      expect_text(editor, text)
      verify_document(editor, text)
      guard integer(button, 30086) == 1 else {
        fail("Value request changed scene")
      }
    }
    guard post(hwnd, 0x0102U, 0x5AUL, 0L) != 0 else {
      fail("ordinary text message failed")
    }
    expect_text(editor, "再入力 🚀Z")
    guard post(hwnd, 0x0100U, 0x08UL, 0L) != 0 else {
      fail("ordinary backspace message failed")
    }
    expect_text(editor, "再入力 🚀")
    verify_task_controls(hwnd, root[0], editor)
    let request = child_named(root[0], "Load user")
    guard request != 0UL else { fail("shared request button missing") }
    defer ignore(release_node(request))
    assert_eq(integer(request, 30003), 50000)
    assert_eq(bounds_width(request), 176.0)
    let request_provider = FixedArray::make(1, 0UL)
    assert_eq(pattern(request, 10000, request_provider), 0)
    guard request_provider[0] != 0UL else {
      fail("request Invoke pattern missing")
    }
    defer ignore(release_pattern(request_provider[0]))
    let scene_y = bounds_component(button, 1)
    request_action(hwnd, request, request_provider[0])
    let mut result_node = 0UL
    stage("HTTP requested")
    for _ in 0..<500 {
      result_node = child_named(root[0], "月兎")
      if result_node != 0UL {
        break
      }
      @async.sleep(20)
    }
    guard result_node != 0UL else { fail("production HTTP result missing") }
    defer ignore(release_node(result_node))
    stage("HTTP result observed")
    assert_eq(bounds_component(button, 1), scene_y)
    expect_text(editor, "再入力 🚀")
    if @env.get_env_var("METONIC_PRESENTATION_CAPTURE") == Some("1") {
      let long_text = "一行目\n二行目\n三行目\n四行目"
      assert_eq(set_value(value_provider[0], utf16z(long_text)), 0)
      expect_text(editor, long_text)
      capture_presentation(hwnd, "long-editor")
      assert_eq(set_value(value_provider[0], utf16z("再入力 🚀")), 0)
      expect_text(editor, "再入力 🚀")
      capture_presentation(hwnd, "result")
    }
    let before = FixedArray::make(4, 0)
    guard client_rect(hwnd, before) != 0 else {
      fail("initial client bounds missing")
    }
    guard resize_window(hwnd, 0UL, 0, 0, 480, 300, 22U) != 0 else {
      fail("production resize failed")
    }
    let rect = FixedArray::make(4, 0)
    let mut resized = false
    for _ in 0..<500 {
      if client_rect(hwnd, rect) != 0 &&
        rect[2] != before[2] &&
        bounds_width(editor) == (rect[2] - 16).max(1).min(640).to_double() {
        resized = true
        break
      }
      @async.sleep(20)
    }
    guard resized else {
      fail("production resize did not update semantic layout")
    }
    guard text_is(result_node, 30005, "月兎") && integer(button, 30086) == 1 else {
      fail("resize changed HTTP result or scene")
    }
    assert_eq(focus_node(editor), 0)
    expect_focus(editor)
    guard post(hwnd, 0x0102U, 0x51UL, 0L) != 0 else {
      fail("editing after HTTP and resize failed")
    }
    expect_text(editor, "再入力 🚀Q")
    capture_presentation(hwnd, "resized")
    verify_task_controls(hwnd, root[0], editor, expected_text="再入力 🚀Q")
    guard text_is(result_node, 30005, "月兎") else {
      fail("compact task controls changed HTTP result")
    }
    capture_presentation(hwnd, "compact-completed")
    guard post(hwnd, 0x0010U, 0UL, 0L) != 0 else {
      fail("production close failed")
    }
    for _ in 0..<500 {
      if is_window(hwnd) == 0 {
        break
      }
      @async.sleep(20)
    }
    guard is_window(hwnd) == 0 else { fail("production UIA close failed") }
    guard toggle(provider[0]) < 0 else {
      fail("closed production provider accepted action")
    }
    guard invoke(request_provider[0]) < 0 else {
      fail("closed request button accepted action")
    }
    guard set_value(value_provider[0], utf16z("late")) < 0 else {
      fail("closed editor accepted Value request")
    }
    println(
      "WINDOW_PRODUCTION_UIA_OK shared_text toggle_update value_roundtrip=4 ordinary_edit http_result resize edit_after_resize close stale_provider",
    )
  })
}
