///|
extern "C" fn current_pid() -> UInt = "GetCurrentProcessId"

///|
extern "C" fn next_owned_window(
  parent : UInt64,
  after : UInt64,
  class_name : UInt64,
  title : UInt64,
) -> UInt64 = "FindWindowExW"

///|
#borrow(pid)
extern "C" fn pointer_window_owner(
  window : UInt64,
  pid : FixedArray[UInt],
) -> UInt = "GetWindowThreadProcessId"

///|
#borrow(rect)
extern "C" fn pointer_client_rect(
  window : UInt64,
  rect : FixedArray[Int],
) -> Int = "GetClientRect"

///|
extern "C" fn pointer_post(
  window : UInt64,
  message : UInt,
  key : UInt64,
  point : Int64,
) -> Int = "PostMessageW"

///|
fn notes_window() -> UInt64 raise {
  let mut cursor = 0UL
  let mut found = 0UL
  let pid = FixedArray::make(1, 0U)
  let rect = FixedArray::make(4, 0)
  for _ in 0..<4096 {
    cursor = next_owned_window(0UL, cursor, 0UL, 0UL)
    if cursor == 0UL {
      assert_true(found != 0UL, msg="Owned notes window missing")
      return found
    }
    if pointer_window_owner(cursor, pid) != 0U &&
      pid[0] == current_pid() &&
      pointer_client_rect(cursor, rect) != 0 &&
      rect[2] == 480 &&
      rect[3] == 240 {
      assert_eq(found, 0UL, msg="Ambiguous owned notes window")
      found = cursor
    }
  }
  fail("Owned notes window enumeration exceeded its bound")
}

///|
fn pointer_click(window : UInt64, x : Int, y : Int) -> Unit raise {
  let point = (y * 65536 + x).to_int64()
  assert_true(pointer_post(window, 0x201U, 1UL, point) != 0)
  assert_true(pointer_post(window, 0x202U, 0UL, point) != 0)
}

///|
async fn verify_disabled_pointer(
  model : @notes.Model,
  handle : @window_host.Handle,
  activations : Ref[Int],
) -> Unit {
  let window = notes_window()
  let original = @semantics.node(model.editor, model.note).unwrap()
  assert_eq(@semantics.set_enabled(model.editor, model.note, false), "")
  let previous = activations.val
  pointer_click(window, 64, 144)
  @async.with_timeout(2000, () => {
    while activations.val == previous {
      @async.sleep(5)
    }
  })
  assert_eq(activations.val, previous + 1)
  assert_true(@semantics.node(model.editor, model.clear).unwrap().focused)
  pointer_click(window, 60, 40)
  assert_true(pointer_post(window, 0x102U, 88UL, 0L) != 0)
  @async.sleep(30)
  ignore((handle.capture)(_ => ()))
  let disabled = @semantics.node(model.editor, model.note).unwrap()
  assert_false(disabled.enabled)
  assert_false(disabled.focused)
  assert_eq(disabled.value, original.value)
  assert_eq(disabled.selection_start, original.selection_start)
  assert_eq(disabled.selection_end, original.selection_end)
  assert_eq(@semantics.set_enabled(model.editor, model.note, true), "")
  assert_eq(@semantics.focus(model.editor, model.note), "")
  println("NOTES_DISABLED_INPUT_POINTER_OK button_activated input_unchanged")
}
