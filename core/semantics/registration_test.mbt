///|
test "an empty tree supports inputs before buttons and independent focus" {
  let tree = empty(7, 8)
  assert_eq(snapshot(tree).length(), 0)
  let first = add_input(tree, "Title", "abcd").unwrap()
  let second = add_input(tree, "Notes", "日本語").unwrap()
  let button = add_button(tree, "Save").unwrap()
  assert_eq(set_selection(tree, first, 1, 3), "")
  assert_eq(replace_selection(tree, first, "X"), "")
  assert_eq(snapshot(tree)[0].value, "aXd")
  assert_eq(focus(tree, second), "")
  assert_eq(focus(tree, button), "")
  assert_false(snapshot(tree)[1].focused)
  assert_true(snapshot(tree)[2].focused)
  assert_eq(set_enabled(tree, button, false), "")
  assert_false(snapshot(tree)[2].focused)
  assert_eq(remove(tree, first), "")
  assert_eq(set_text(tree, first, "stale"), "stale_target")
  assert_eq(snapshot(tree)[0].reference, second)
  assert_true(dispose(tree))
  assert_eq(set_text(tree, second, "closed"), "closed")
}

///|
test "renaming preserves identity and editing state and invalidates accessibility once" {
  let tree = empty(7, 8)
  let input = add_input(tree, "Memo", "日本語").unwrap()
  let button = add_button(tree, "First memo").unwrap()
  assert_eq(set_selection(tree, input, 0, 2), "")
  assert_eq(focus(tree, input), "")
  let before = revision(tree)
  assert_eq(set_name(tree, input, "Selected memo"), "")
  let renamed = node(tree, input).unwrap()
  assert_eq(renamed.name, "Selected memo")
  assert_eq(renamed.value, "日本語")
  assert_eq(renamed.selection_start, 0)
  assert_eq(renamed.selection_end, 2)
  assert_true(renamed.focused)
  assert_eq(revision(tree), before + 1)
  assert_eq(set_name(tree, input, "Selected memo"), "")
  assert_eq(revision(tree), before + 1)
  assert_eq(set_enabled(tree, button, false), "")
  assert_eq(set_name(tree, button, "No memo"), "")
  assert_false(node(tree, button).unwrap().enabled)
  assert_eq(node(tree, button).unwrap().name, "No memo")
  assert_eq(remove(tree, button), "")
  assert_eq(set_name(tree, button, "stale"), "stale_target")
  assert_true(dispose(tree))
  assert_eq(set_name(tree, input, "closed"), "closed")
}

///|
test "explicit composition and restored slots preserve target generations" {
  let tree = create(4, 9, [
    { role: TextInput, name: "Draft", value: "abc", },
    { role: Button, name: "Publish", value: "idle", },
  ]).unwrap()
  let input = snapshot(tree)[0].reference
  let button = snapshot(tree)[1].reference
  assert_eq(revision(tree), 0)
  assert_eq(set_button_value(tree, button, "ready"), "")
  assert_eq(snapshot(tree)[1].value, "ready")
  assert_eq(set_selection(tree, input, 0, 2), "")
  let composition = begin_composition(tree, target=input).unwrap()
  assert_eq(composition.preview("あ"), Some("あc"))
  assert_eq(remove(tree, input), "")
  let fresh = restore_input(tree, input.id, "Replacement", "xyz").unwrap()
  assert_true(fresh.generation != input.generation)
  assert_eq(set_text(tree, input, "stale"), "stale_target")
  assert_eq(composition.preview("late"), None)
  assert_eq(set_text(tree, fresh, "fresh"), "")
  assert_eq(restore_input(tree, fresh.id, "Duplicate", ""), None)
  assert_eq(restore_input(tree, 999, "Unissued", ""), None)
}
