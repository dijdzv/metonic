///|
extern "C" fn identity_test_pid() -> Int = "GetCurrentProcessId"

///|
#borrow(class_name, title)
extern "C" fn identity_test_create(
  extended_style : UInt,
  class_name : FixedArray[Byte],
  title : FixedArray[Byte],
  style : UInt,
  x : Int,
  y : Int,
  width : Int,
  height : Int,
  parent : UInt64,
  menu : UInt64,
  instance : UInt64,
  parameter : UInt64,
) -> UInt64 = "CreateWindowExW"

///|
extern "C" fn identity_test_destroy(hwnd : UInt64) -> Int = "DestroyWindow"

///|
fn identity_test_window(title : String, shown~ : Bool = true) -> UInt64 raise {
  let hwnd = identity_test_create(
    0U, utf16z("STATIC"), utf16z(title),
    if shown { 0x90000000U } else { 0x80000000U },
    -30000, -30000, 1, 1, 0UL, 0UL, 0UL, 0UL,
  )
  assert_true(hwnd != 0UL)
  hwnd
}

///|
test "close target excludes same-process helper, title prefix and hidden windows" {
  let pid = identity_test_pid()
  let helper = identity_test_window("Helper")
  defer ignore(identity_test_destroy(helper))
  let prefix = identity_test_window("Metonic helper")
  defer ignore(identity_test_destroy(prefix))
  let hidden = identity_test_window("Metonic", shown=false)
  defer ignore(identity_test_destroy(hidden))
  assert_eq(owned_window(pid), 0UL)
  let app = identity_test_window("Metonic")
  defer ignore(identity_test_destroy(app))
  assert_eq(owned_window(pid), app)
  assert_eq(owned_window(-1), 0UL)
  {
    let duplicate = identity_test_window("Metonic")
    defer ignore(identity_test_destroy(duplicate))
    let rejected = try {
      ignore(owned_window(pid))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  assert_eq(owned_window(pid), app)
  assert_eq(is_window(helper), 1)
  assert_eq(is_window(prefix), 1)
}
