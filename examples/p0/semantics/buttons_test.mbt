///|
test "additional action focus and removal do not mutate the editor" {
  let tree = create(1, 1)
  let input = snapshot(tree)[1].reference
  assert_eq(set_text(tree, input, "preserved"), "")
  let action = add_button(tree, "Load user").unwrap()
  assert_eq(focus(tree, action), "")
  assert_eq(snapshot(tree)[2].focused, true)
  assert_eq(focus(tree, input), "")
  assert_eq(snapshot(tree)[2].focused, false)
  assert_eq(set_enabled(tree, action, false), "")
  assert_eq(focus(tree, action), "disabled")
  assert_eq(remove(tree, action), "")
  assert_eq(snapshot(tree)[1].value, "preserved")
  assert_eq(focus(tree, action), "stale_target")
  assert_eq(dispose(tree), true)
  assert_eq(add_button(tree, "late"), None)
}
