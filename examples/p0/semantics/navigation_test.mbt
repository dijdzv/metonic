///|
test "shift navigation reverses through the anchor without splitting a surrogate" {
  let tree = create(1, 1)
  let reference = snapshot(tree)[1].reference
  assert_eq(set_text(tree, reference, "A😀語"), "")
  assert_eq(set_selection(tree, reference, 3, 3), "")
  assert_eq(navigate(tree, reference, false, true), "")
  let node = snapshot(tree)[1]
  assert_eq(
    (
      node.selection_start,
      node.selection_end,
      node.selection_anchor,
      caret(node),
    ),
    (1, 3, 3, 1),
  )
  assert_eq(navigate(tree, reference, true, true), "")
  assert_eq(caret(snapshot(tree)[1]), 3)
  assert_eq(navigate(tree, reference, true, true), "")
  let node = snapshot(tree)[1]
  assert_eq(
    (
      node.selection_start,
      node.selection_end,
      node.selection_anchor,
      caret(node),
    ),
    (3, 4, 3, 4),
  )
  assert_eq(replace_selection(tree, reference, "B"), "")
  assert_eq(snapshot(tree)[1].value, "A😀B")
  assert_eq(snapshot(tree)[1].selection_anchor, 4)
}

///|
test "unmodified arrows collapse a range and stop at text boundaries" {
  let tree = create(1, 1)
  let reference = snapshot(tree)[1].reference
  assert_eq(set_text(tree, reference, "A😀語"), "")
  assert_eq(set_selection_directed(tree, reference, 4, 1), "")
  assert_eq(navigate(tree, reference, false, false), "")
  assert_eq(caret(snapshot(tree)[1]), 1)
  assert_eq(navigate(tree, reference, true, false), "")
  assert_eq(caret(snapshot(tree)[1]), 3)
  assert_eq(set_selection(tree, reference, 0, 0), "")
  let before = revision(tree)
  assert_eq(navigate(tree, reference, false, false), "")
  assert_eq(revision(tree), before)
  assert_eq(set_selection_directed(tree, reference, 0, 2), "invalid_selection")
  assert_eq(set_enabled(tree, reference, false), "")
  assert_eq(navigate(tree, reference, true, false), "disabled")
  assert_eq(remove(tree, reference), "")
  assert_eq(navigate(tree, reference, true, false), "stale_target")
}
