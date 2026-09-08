///|
extern "C" fn window() -> UInt64 = "metonic_sdk_window"

///|
extern "C" fn show(hwnd : UInt64) -> Unit = "metonic_sdk_show"

///|
extern "C" fn destroy(hwnd : UInt64) -> Unit = "metonic_sdk_destroy"

///|
extern "C" fn open(
  hwnd : UInt64,
  activate : FuncRef[(UInt64) -> UInt64],
) -> UInt64 = "metonic_accesskit_open"

///|
extern "C" fn close(adapter : UInt64) -> Unit = "metonic_accesskit_close"

///|
extern "C" fn start(hwnd : UInt64, pause : Int) -> Int = "metonic_sdk_start"

///|
extern "C" fn wait_entered() -> Int = "metonic_sdk_wait_entered"

///|
extern "C" fn finish() -> Int = "metonic_sdk_finish"

///|
extern "C" fn metric(field : Int) -> Int = "metonic_sdk_metric"

///|
extern "C" fn take() -> UInt64 = "metonic_accesskit_take"

///|
extern "C" fn request_node(request : UInt64) -> UInt64 = "metonic_accesskit_node"

///|
extern "C" fn request_action(request : UInt64) -> Int = "metonic_accesskit_action"

///|
extern "C" fn free(request : UInt64) -> Unit = "metonic_sdk_free"

///|
extern "C" fn node(role : Int) -> UInt64 = "accesskit_node_new"

///|
extern "C" fn label(node : UInt64) -> Unit = "metonic_sdk_label"

///|
extern "C" fn child(node : UInt64, id : UInt64) -> Unit = "accesskit_node_push_child"

///|
extern "C" fn action(node : UInt64, action : Int) -> Unit = "accesskit_node_add_action"

///|
extern "C" fn bounds(
  node : UInt64,
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> Unit = "metonic_accesskit_bounds"

///|
extern "C" fn tree(root : UInt64) -> UInt64 = "accesskit_tree_new"

///|
extern "C" fn update(focus : UInt64) -> UInt64 = "accesskit_tree_update_with_focus"

///|
extern "C" fn set_tree(update : UInt64, tree : UInt64) -> Unit = "accesskit_tree_update_set_tree"

///|
extern "C" fn push(update : UInt64, id : UInt64, node : UInt64) -> Unit = "accesskit_tree_update_push_node"

///|
fn activate(_data : UInt64) -> UInt64 {
  let root = node(114)
  let button = node(18)
  label(button)
  action(button, 0)
  bounds(root, 0.0, 0.0, 300.0, 160.0)
  bounds(button, 8.0, 8.0, 120.0, 40.0)
  child(root, 1UL)
  let result = update(1UL)
  set_tree(result, tree(0UL))
  push(result, 0UL, root)
  push(result, 1UL, button)
  result
}

///|
fn main raise {
  let first = window()
  assert_true(first != 0UL)
  let old = open(first, data => activate(data))
  assert_true(old != 0UL)
  show(first)
  assert_eq(start(first, 1), 1)
  assert_eq(wait_entered(), 1)
  close(old)
  destroy(first)
  let second = window()
  assert_true(second != 0UL)
  let current = open(second, data => activate(data))
  assert_true(current != 0UL)
  show(second)
  assert_eq(finish(), 1)
  assert_eq(metric(4), 1)
  assert_eq(metric(0), metric(1))
  assert_eq(take(), 0UL)
  assert_eq(start(second, 0), 1)
  assert_eq(finish(), 1)
  assert_true(metric(3) >= 0)
  let mut received_clicks = 0
  for _ in 0..<32 {
    let request = take()
    if request == 0UL {
      break
    }
    let action = request_action(request)
    let target = request_node(request)
    free(request)
    assert_eq(target, 1UL)
    assert_true(action == 0 || action == 1)
    if action == 0 {
      received_clicks += 1
    }
  }
  assert_eq(received_clicks, 1)
  close(current)
  destroy(second)
  assert_eq(metric(0), metric(1))
  assert_eq(metric(4), 2)
  assert_eq(metric(2), 0)
  println(
    "SDK_MAILBOX_LIFETIME_OK old_callback_rejected fresh_callback_received all_freed",
  )
}
