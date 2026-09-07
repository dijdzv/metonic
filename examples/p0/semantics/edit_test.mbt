///|
test "backspace removes a scalar or selection and beginning is unchanged" {
  let tree = create(1, 1)
  let input = snapshot(tree)[1].reference
  assert_eq(set_text(tree, input, "A😀語"), "")
  assert_eq(set_selection(tree, input, 3, 3), "")
  let before = revision(tree)
  assert_eq(delete_backward(tree, input), "")
  assert_eq(snapshot(tree)[1].value, "A語")
  assert_eq(snapshot(tree)[1].selection_start, 1)
  assert_eq(revision(tree), before + 1)
  assert_eq(set_selection(tree, input, 0, 2), "")
  assert_eq(delete_backward(tree, input), "")
  assert_eq(snapshot(tree)[1].value, "")
  let before = revision(tree)
  assert_eq(delete_backward(tree, input), "")
  assert_eq(revision(tree), before)
  assert_eq(set_enabled(tree, input, false), "")
  assert_eq(delete_backward(tree, input), "disabled")
}

///|
test "selection replacement is one revision and preserves supplementary characters" {
  let tree = create(1, 1)
  let input = snapshot(tree)[1].reference
  assert_eq(set_text(tree, input, "A😀日本B"), "")
  assert_eq(set_selection(tree, input, 3, 5), "")
  let before = revision(tree)
  assert_eq(replace_selection(tree, input, "語😀"), "")
  let node = snapshot(tree)[1]
  assert_eq(node.value, "A😀語😀B")
  assert_eq(node.selection_start, 6)
  assert_eq(node.selection_end, 6)
  assert_eq(revision(tree), before + 1)
  assert_eq(replace_selection(tree, input, ""), "")
  assert_eq(revision(tree), before + 1)
}

///|
test "empty replacement deletes selection and disabled or stale edits do not mutate" {
  let tree = create(1, 1)
  let input = snapshot(tree)[1].reference
  assert_eq(set_text(tree, input, "日本語"), "")
  assert_eq(set_selection(tree, input, 0, 2), "")
  assert_eq(replace_selection(tree, input, ""), "")
  assert_eq(snapshot(tree)[1].value, "語")
  assert_eq(set_enabled(tree, input, false), "")
  let before = revision(tree)
  assert_eq(replace_selection(tree, input, "x"), "disabled")
  assert_eq(revision(tree), before)
  assert_eq(remove(tree, input), "")
  ignore(recreate_input(tree))
  let before = revision(tree)
  assert_eq(replace_selection(tree, input, "x"), "stale_target")
  assert_eq(revision(tree), before)
}
