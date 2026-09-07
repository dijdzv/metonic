///|
test "preedit preserves committed text and selection until one commit" {
  let tree = create(1, 1)
  let input = snapshot(tree)[1].reference
  assert_eq(set_text(tree, input, "A😀B"), "")
  assert_eq(set_selection(tree, input, 1, 3), "")
  let before = revision(tree)
  let composition = begin_composition(tree).unwrap()
  assert_eq(composition.preview("にほん"), Some("AにほんB"))
  assert_eq(snapshot(tree)[1].value, "A😀B")
  assert_eq(snapshot(tree)[1].selection_start, 1)
  assert_eq(snapshot(tree)[1].selection_end, 3)
  assert_eq(revision(tree), before)
  assert_eq(composition.commit("日本"), "")
  assert_eq(snapshot(tree)[1].value, "A日本B")
  assert_eq(revision(tree), before + 1)
  assert_eq(composition.commit("duplicate"), "composition_ended")
}

///|
test "cancel and intervening edits invalidate composition without changing text" {
  let tree = create(1, 1)
  let input = snapshot(tree)[1].reference
  assert_eq(set_text(tree, input, "original"), "")
  let canceled = begin_composition(tree).unwrap()
  canceled.cancel()
  assert_eq(canceled.preview("discard"), None)
  assert_eq(canceled.commit("discard"), "composition_ended")
  assert_eq(snapshot(tree)[1].value, "original")
  let stale = begin_composition(tree).unwrap()
  assert_eq(set_text(tree, input, "new"), "")
  assert_eq(stale.preview("old"), None)
  assert_eq(stale.commit("old"), "stale_composition")
  assert_eq(snapshot(tree)[1].value, "new")
  let disposed = begin_composition(tree).unwrap()
  ignore(dispose(tree))
  assert_eq(disposed.commit("old"), "stale_composition")
}
