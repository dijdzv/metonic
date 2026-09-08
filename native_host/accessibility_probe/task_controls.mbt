///|
extern "C" fn uptime_ms() -> UInt64 = "GetTickCount64"

///|
async fn expect_task(root : UInt64, expected : String) -> Unit {
  let began = uptime_ms()
  while uptime_ms() - began < 5000UL {
    let node = child_named(root, expected)
    if node != 0UL {
      stage("task observed " + expected + " at=" + uptime_ms().to_string())
      ignore(release_node(node))
      return
    }
    @async.sleep(20)
  }
  for
    candidate in [
      "Idle", "Working...", "Completed", "Failed", "Canceled", "Stopped",
    ] {
    let node = child_named(root, candidate)
    if node != 0UL {
      stage(
        "observed task state while expecting " + expected + ": " + candidate,
      )
      ignore(release_node(node))
    }
  }
  fail("shared task status missing: " + expected)
}

///|
async fn verify_task_controls(
  hwnd : UInt64,
  root : UInt64,
  editor : UInt64,
  expected_text? : String = "再入力 🚀",
) -> Unit {
  let start = child_named(root, "Move after delay")
  guard start != 0UL else { fail("shared start button missing") }
  defer ignore(release_node(start))
  let cancel = child_named(root, "Cancel")
  guard cancel != 0UL else { fail("shared cancel button missing") }
  defer ignore(release_node(cancel))
  let start_provider = FixedArray::make(1, 0UL)
  let cancel_provider = FixedArray::make(1, 0UL)
  assert_eq(pattern(start, 10000, start_provider), 0)
  assert_true(start_provider[0] != 0UL)
  defer ignore(release_pattern(start_provider[0]))
  assert_eq(pattern(cancel, 10000, cancel_provider), 0)
  assert_true(cancel_provider[0] != 0UL)
  defer ignore(release_pattern(cancel_provider[0]))
  request_action(hwnd, start, start_provider[0])
  expect_task(root, "Working...")
  request_action(hwnd, cancel, cancel_provider[0])
  expect_task(root, "Canceled")
  @async.sleep(1100)
  expect_task(root, "Canceled")
  expect_text(editor, expected_text)
  request_action(hwnd, start, start_provider[0])
  expect_task(root, "Working...")
  expect_task(root, "Completed")
  expect_text(editor, expected_text)
  stage("shared task controls cancel and reuse passed")
}
