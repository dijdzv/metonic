///|
test "direct text input preserves limits and selection boundaries for both fields" {
  for query in [false, true] {
    reset_state()
    assert_eq(input_commit(query, "A😀日本", 1, 3), 1)
    let state = fn() {
      (
        @semantics.revision(application.val.editor),
        @semantics.snapshot(application.val.editor).map(node => {
          (node.value, node.selection_start, node.selection_end)
        }),
      )
    }
    let before = state()
    assert_eq(input_commit(query, "A😀日本", 2, 3), 0)
    assert_eq(input_commit(query, "other", 4, 2), 0)
    assert_eq(
      input_commit(query, String::from_array(Array::make(1025, 'x')), 0, 0),
      0,
    )
    assert_eq(state(), before)
    let started = if query {
      query_composition_start()
    } else {
      editor_composition_start()
    }
    assert_eq(started, 1)
    assert_eq(input_commit(query, "premature", 0, 0), 0)
    assert_eq(input_preedit(query, "にほん"), 1)
    assert_eq(input_cursor(query, "Aにほん日本", 2), 1)
    assert_eq(input_cursor(query, "mismatched DOM value", 2), 0)
    assert_eq(input_cursor(query, "Aにほん日本", 0), 0)
    assert_eq(state(), before)
    if query {
      query_composition_end()
    } else {
      editor_composition_end()
    }
    assert_eq(input_preedit(query, "late"), 0)
    assert_eq(input_cursor(query, "Aにほん日本", 2), 0)
    assert_eq(input_commit(query, "A日本", 3, 3), 1)
  }
}
