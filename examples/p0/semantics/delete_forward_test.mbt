///|
test "forward deletion preserves scalar and CRLF boundaries" {
  for
    entry in [
      ("A日本", 1, "A本", 1),
      ("A😀B", 1, "AB", 1),
      ("A\r\nB", 1, "AB", 1),
      ("\rX\n", 1, "\r\n", 2),
    ] {
    let (text, position, expected, expected_caret) = entry
    let tree = create(1, 1)
    let input = snapshot(tree)[1].reference
    assert_eq(set_text(tree, input, text), "")
    assert_eq(set_selection(tree, input, position, position), "")
    let before = revision(tree)
    assert_eq(delete_forward(tree, input), "")
    let node = snapshot(tree)[1]
    assert_eq(node.value, expected)
    assert_eq(caret(node), expected_caret)
    assert_eq(node.selection_start, node.selection_end)
    assert_eq(revision(tree), before + 1)
  }
}

///|
test "forward deletion removes either directed selection and is inert at end" {
  for range in [(1, 4), (4, 1)] {
    let (anchor, end) = range
    let tree = create(1, 1)
    let input = snapshot(tree)[1].reference
    assert_eq(set_text(tree, input, "A😀日B"), "")
    assert_eq(set_selection_directed(tree, input, anchor, end), "")
    assert_eq(delete_forward(tree, input), "")
    assert_eq(snapshot(tree)[1].value, "AB")
    assert_eq(caret(snapshot(tree)[1]), 1)
    assert_eq(set_selection(tree, input, 2, 2), "")
    let before = revision(tree)
    assert_eq(delete_forward(tree, input), "")
    assert_eq(revision(tree), before)
    assert_eq(snapshot(tree)[1].value, "AB")
  }
}

///|
test "forward deletion rejects disabled and stale targets" {
  let tree = create(1, 1)
  let input = snapshot(tree)[1].reference
  assert_eq(set_text(tree, input, "日本"), "")
  assert_eq(set_selection(tree, input, 0, 0), "")
  assert_eq(set_enabled(tree, input, false), "")
  assert_eq(delete_forward(tree, input), "disabled")
  assert_eq(snapshot(tree)[1].value, "日本")
  assert_eq(
    delete_forward(tree, snapshot(tree)[0].reference),
    "unsupported_action",
  )
  assert_eq(remove(tree, input), "")
  assert_eq(delete_forward(tree, input), "stale_target")
}
