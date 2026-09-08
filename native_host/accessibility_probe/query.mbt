///|
async fn verify_query(
  hwnd : UInt64,
  root : UInt64,
  editor : UInt64,
  request : UInt64,
  provider : UInt64,
) -> Unit {
  let query = child_named(root, "User ID")
  guard query != 0UL else { fail("query input missing") }
  defer ignore(release_node(query))
  let value = FixedArray::make(1, 0UL)
  assert_eq(pattern(query, 10002, value), 0)
  guard value[0] != 0UL else { fail("query Value pattern missing") }
  defer ignore(release_pattern(value[0]))
  expect_text(query, "1")
  assert_eq(focus_node(query), 0)
  expect_focus(query)
  assert_true(post(hwnd, 0x0100U, 0x08UL, 0L) != 0)
  expect_text(query, "")
  assert_true(post(hwnd, 0x0102U, 0x31UL, 0L) != 0)
  expect_text(query, "1")
  expect_text(editor, "再入力 🚀")
  for
    entry in [
      ("1", "月兎"),
      ("missing", "RPC: domain:not_found"),
      ("1", "月兎"),
    ] {
    let (id, expected) = entry
    assert_eq(set_value(value[0], utf16z(id)), 0)
    expect_text(query, id)
    request_action(hwnd, request, provider)
    let mut observed = false
    for _ in 0..<500 {
      let result = child_named(root, expected)
      if result != 0UL {
        ignore(release_node(result))
        observed = true
        break
      }
      @async.sleep(20)
    }
    guard observed else { fail("query result missing: " + expected) }
    expect_text(query, id)
    expect_text(editor, "再入力 🚀")
  }
  stage("query success, domain error and retry preserved editor")
}
