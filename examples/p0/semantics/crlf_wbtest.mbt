///|
test "CRLF is one editable line break without changing UTF-16 offsets" {
  let tree = create(1, 1)
  let reference = snapshot(tree)[1].reference
  assert_eq(set_text(tree, reference, "A\r\nB"), "")
  assert_eq(set_selection(tree, reference, 2, 2), "invalid_selection")
  assert_eq(set_selection(tree, reference, 1, 1), "")
  assert_eq(navigate(tree, reference, true, false), "")
  assert_eq(caret(snapshot(tree)[1]), 3)
  assert_eq(navigate(tree, reference, false, true), "")
  let selected = snapshot(tree)[1]
  assert_eq(
    (
      selected.selection_start,
      selected.selection_end,
      selected.selection_anchor,
    ),
    (1, 3, 3),
  )
  assert_eq(replace_selection(tree, reference, "日"), "")
  assert_eq(snapshot(tree)[1].value, "A日B")
  assert_eq(set_text(tree, reference, "A\r\nB"), "")
  assert_eq(set_selection(tree, reference, 3, 3), "")
  assert_eq(delete_backward(tree, reference), "")
  assert_eq(snapshot(tree)[1].value, "AB")
  assert_eq(caret(snapshot(tree)[1]), 1)
  assert_eq(set_text(tree, reference, "A\nB"), "")
  assert_eq(set_selection(tree, reference, 1, 1), "")
  assert_eq(replace_selection(tree, reference, "\r"), "")
  assert_eq(snapshot(tree)[1].value, "A\r\nB")
  assert_eq(caret(snapshot(tree)[1]), 3)
  assert_eq(set_text(tree, reference, "A\rX\nB"), "")
  assert_eq(set_selection(tree, reference, 3, 3), "")
  assert_eq(delete_backward(tree, reference), "")
  assert_eq(snapshot(tree)[1].value, "A\r\nB")
  assert_eq(caret(snapshot(tree)[1]), 3)
}
