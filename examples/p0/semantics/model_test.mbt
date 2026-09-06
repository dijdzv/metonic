///|
test "stale after recreate and cross session" {
  let tree = create(1, 2)
  let old = snapshot(tree)[1].reference
  assert_eq(remove(tree, old), "")
  let fresh = recreate_input(tree).unwrap()
  assert_eq(set_text(tree, old, "old"), "stale_target")
  assert_eq(
    set_text(
      tree,
      { session: 9, window: 2, id: 2, generation: fresh.generation, },
      "x",
    ),
    "stale_target",
  )
}

///|
test "wrong role and focus exclusivity" {
  let tree = create(1, 1)
  let button = snapshot(tree)[0].reference
  let input = snapshot(tree)[1].reference
  assert_eq(set_text(tree, button, "x"), "unsupported_action")
  assert_eq(focus(tree, button), "")
  assert_eq(focus(tree, input), "")
  assert_eq(snapshot(tree)[0].focused, false)
  assert_eq(snapshot(tree)[1].focused, true)
}

///|
test "text selection uses value length" {
  let tree = create(1, 1)
  let input = snapshot(tree)[1].reference
  assert_eq(set_text(tree, input, "日本語"), "")
  let node = snapshot(tree)[1]
  assert_eq(node.value, "日本語")
  assert_eq(node.selection_start, node.value.length())
  assert_eq(node.selection_end, node.value.length())
}

///|
test "dispose clears snapshot and is terminal" {
  let tree = create(1, 1)
  assert_eq(dispose(tree), true)
  assert_eq(snapshot(tree).length(), 0)
  assert_eq(dispose(tree), false)
  assert_eq(recreate_input(tree), None)
}

///|
test "snapshot nodes stay immutable after activation" {
  let tree = create(1, 1)
  let before = snapshot(tree)[0]
  ignore(activate(tree, before.reference))
  assert_eq(before.value, "off")
  assert_eq(snapshot(tree)[0].value, "on")
}

///|
test "cross window and disabled operations are rejected" {
  let tree = create(1, 1)
  let button = snapshot(tree)[0].reference
  let input = snapshot(tree)[1].reference
  let foreign : NodeRef = {
    session: 1,
    window: 2,
    id: button.id,
    generation: button.generation,
  }
  assert_eq(activate(tree, foreign), "stale_target")
  assert_eq(set_enabled(tree, button, false), "")
  assert_eq(focus(tree, button), "disabled")
  assert_eq(activate(tree, button), "disabled")
  assert_eq(set_text(tree, input, "x"), "")
  assert_eq(set_enabled(tree, input, false), "")
  assert_eq(set_text(tree, input, "y"), "disabled")
}

///|
test "selection uses UTF16 boundaries" {
  let tree = create(1, 1)
  let input = snapshot(tree)[1].reference
  ignore(set_text(tree, input, "A😀B"))
  assert_eq(set_selection(tree, input, 0, 4), "")
  assert_eq(set_selection(tree, input, 2, 2), "invalid_selection")
  assert_eq(set_selection(tree, input, 0, 5), "invalid_selection")
}
