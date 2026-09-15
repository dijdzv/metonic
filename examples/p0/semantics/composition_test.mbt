///|
test "replacement cancellation keeps selection deletion but discards preedit" {
  for selected in [(0, 3), (1, 2)] {
    let tree = create(1, 1)
    let input = snapshot(tree)[1].reference
    let (start, end) = selected
    assert_eq(set_text(tree, input, "あいう"), "")
    assert_eq(set_selection(tree, input, start, end), "")
    let original = begin_composition(tree).unwrap()
    let replacement = original.remove_selected_text().unwrap()
    let expected = if start == 0 { "" } else { "あう" }
    assert_eq(snapshot(tree)[1].value, expected)
    assert_eq(snapshot(tree)[1].selection_start, start)
    assert_eq(snapshot(tree)[1].selection_end, start)
    assert_eq(original.preview("late"), None)
    let current_revision = revision(tree)
    let replacement = replacement.remove_selected_text().unwrap()
    assert_eq(revision(tree), current_revision)
    assert_eq(
      replacement.presentation("あ", 1),
      Some(
        (
          if start == 0 {
            "あ"
          } else {
            "ああう"
          },
          start,
          start + 1,
          start + 1,
        ),
      ),
    )
    replacement.cancel()
    assert_eq(snapshot(tree)[1].value, expected)
    assert_eq(replacement.remove_selected_text() is None, true)
  }
}

///|
test "prepared replacement commits supplementary text without deleting suffix twice" {
  let tree = create(1, 1)
  let input = snapshot(tree)[1].reference
  assert_eq(set_text(tree, input, "A😀B"), "")
  assert_eq(set_selection(tree, input, 1, 3), "")
  let composition = begin_composition(tree)
    .unwrap()
    .remove_selected_text()
    .unwrap()
  assert_eq(snapshot(tree)[1].value, "AB")
  assert_eq(composition.commit("😀"), "")
  assert_eq(snapshot(tree)[1].value, "A😀B")
  assert_eq(snapshot(tree)[1].selection_start, 3)
  assert_eq(snapshot(tree)[1].selection_end, 3)
}

///|
test "replacement preparation rejects stale state without deleting new text" {
  let tree = create(1, 1)
  let input = snapshot(tree)[1].reference
  assert_eq(set_text(tree, input, "あいう"), "")
  assert_eq(set_selection(tree, input, 0, 3), "")
  let composition = begin_composition(tree).unwrap()
  assert_eq(set_text(tree, input, "new"), "")
  assert_eq(composition.remove_selected_text() is None, true)
  assert_eq(snapshot(tree)[1].value, "new")
}

///|
test "composition presentation uses the captured range and rejects invalid or expired cursors" {
  let tree = create(1, 1)
  let input = snapshot(tree)[1].reference
  assert_eq(set_text(tree, input, "A日本B"), "")
  assert_eq(set_selection(tree, input, 1, 3), "")
  let composition = begin_composition(tree).unwrap()
  assert_eq(
    composition.presentation("に😀", 1),
    Some(("Aに😀B", 1, 4, 2)),
  )
  assert_eq(
    composition.presentation("に😀", 3),
    Some(("Aに😀B", 1, 4, 4)),
  )
  assert_eq(composition.presentation("に😀", 2), None)
  assert_eq(composition.presentation("に😀", -1), None)
  assert_eq(composition.presentation("に😀", 4), None)
  assert_eq(snapshot(tree)[1].value, "A日本B")
  composition.cancel()
  assert_eq(composition.presentation("に😀", 1), None)
  let stale = begin_composition(tree).unwrap()
  assert_eq(set_text(tree, input, "changed"), "")
  assert_eq(stale.presentation("に😀", 1), None)
}

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
