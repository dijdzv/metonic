///|
test "query editing and composition preserve the other editor selection" {
  let tree = create(1, 1)
  let editor = snapshot(tree)[1].reference
  assert_eq(set_text(tree, editor, "日本 ABC"), "")
  assert_eq(set_selection(tree, editor, 3, 6), "")
  let query = add_input(tree, "User ID", "1").unwrap()
  assert_eq(focus(tree, query), "")
  assert_eq(set_selection(tree, query, 0, 1), "")
  assert_eq(replace_selection(tree, query, "missing"), "")
  assert_eq(navigate(tree, query, false, false), "")
  assert_eq(delete_backward(tree, query), "")
  assert_eq(snapshot(tree)[2].value, "missig")
  let composition = begin_composition(tree, target=query).unwrap()
  assert_eq(composition.preview("日"), Some("missi日g"))
  assert_eq(composition.commit("本"), "")
  assert_eq(snapshot(tree)[2].value, "missi本g")
  let unchanged = snapshot(tree)[1]
  assert_eq(unchanged.value, "日本 ABC")
  assert_eq(unchanged.selection_start, 3)
  assert_eq(unchanged.selection_end, 6)
  assert_eq(set_enabled(tree, query, false), "")
  assert_eq(set_text(tree, query, "1"), "disabled")
  assert_eq(remove(tree, query), "")
  assert_eq(set_text(tree, query, "1"), "stale_target")
  assert_eq(begin_composition(tree, target=query) is None, true)
}
