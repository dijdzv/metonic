///|
test "unrelated edits and registrations preserve an input composition" {
  let tree = empty(81, 1)
  let input = add_input(tree, "Draft", "abc").unwrap()
  let other = add_input(tree, "Other", "old").unwrap()
  assert_eq(set_selection(tree, input, 0, 2), "")
  let composition = begin_composition(tree, target=input).unwrap()
  assert_eq(set_text(tree, other, "updated"), "")
  ignore(add_button(tree, "Added"))
  assert_eq(composition.preview("青"), Some("青c"))
  assert_eq(composition.commit("青"), "")
  assert_eq(node(tree, input).unwrap().value, "青c")
}

///|
test "target content selection and disabled state invalidate composition" {
  let tree = empty(82, 1)
  let input = add_input(tree, "Draft", "abc").unwrap()
  let changed = begin_composition(tree, target=input).unwrap()
  assert_eq(set_text(tree, input, "model"), "")
  assert_eq(changed.preview("stale"), None)
  assert_eq(changed.commit("stale"), "stale_composition")
  let moved = begin_composition(tree, target=input).unwrap()
  assert_eq(set_selection(tree, input, 0, 1), "")
  assert_eq(moved.commit("stale"), "stale_composition")
  let disabled = begin_composition(tree, target=input).unwrap()
  assert_eq(set_enabled(tree, input, false), "")
  assert_eq(disabled.preview("stale"), None)
  assert_true(disabled.remove_selected_text() is None)
  assert_eq(node(tree, input).unwrap().value, "model")
}
