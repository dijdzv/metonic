///|
test "caret conversion retains the selected side of a visual boundary" {
  let before = selection_cursor("あいうえお", 2)
  let after = selection_cursor("あいうえお", 2, after=true)
  assert_eq(before.line, 0)
  assert_eq(before.index, 2)
  assert_true(before.affinity.before())
  assert_eq(after.line, before.line)
  assert_eq(after.index, before.index)
  assert_true(after.affinity.after())
}

///|
test "caret conversion retains UTF16 offsets across explicit lines" {
  let cursor = selection_cursor("あ\n😀いう", 4, after=true)
  assert_eq(cursor.line, 1)
  assert_eq(cursor.index, 2)
  assert_true(cursor.affinity.after())
  let end = selection_cursor("あ\n", 2, after=true)
  assert_eq(end.line, 1)
  assert_eq(end.index, 0)
  assert_true(end.affinity.after())
}
