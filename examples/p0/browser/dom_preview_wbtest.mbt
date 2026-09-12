///|
test "DOM composition snapshots preserve text without guessing an existing range" {
  for query in [false, true] {
    reset_state()
    assert_eq(input_commit(query, "あうえお", 1, 1), 1)
    let before = @semantics.snapshot(application.val.editor).map(node => {
      (node.value, node.selection_start, node.selection_end)
    })
    assert_eq(
      if query {
        query_composition_start()
      } else {
        editor_composition_start()
      },
      1,
    )
    let preview = if query { query_preview } else { editor_preview }
    let geometry = if query {
      query_preedit_geometry
    } else {
      editor_preedit_geometry
    }
    assert_eq(input_preedit(query, "あ"), 1)
    assert_eq(preview.val, Some("ああうえお"))
    assert_eq(input_dom_preview(query, "あうえお", 1), 1)
    assert_eq(preview.val, Some("あうえお"))
    assert_eq(geometry.val, Some((1, 1, 1)))
    // Repeated text cannot identify which occurrence belongs to the IME.
    assert_eq(input_dom_preview(query, "あああ", 2), 1)
    assert_eq(preview.val, Some("あああ"))
    assert_eq(geometry.val, Some((2, 2, 2)))
    assert_eq(input_dom_preview(query, "😀あ", 1), 0)
    assert_eq(
      input_dom_preview(query, String::from_array(Array::make(1025, 'a')), 0),
      0,
    )
    assert_eq(preview.val, Some("あああ"))
    assert_eq(
      @semantics.snapshot(application.val.editor).map(node => {
        (node.value, node.selection_start, node.selection_end)
      }),
      before,
    )
    if query {
      query_composition_end()
    } else {
      editor_composition_end()
    }
    assert_eq(preview.val, None)
    assert_eq(input_dom_preview(query, "late", 0), 0)
    assert_eq(input_commit(query, "あうえお", 1, 1), 1)
  }
}

///|
test "DOM snapshots retain verified preedit geometry and reject stale composition" {
  for query in [false, true] {
    reset_state()
    assert_eq(input_commit(query, "AB", 1, 1), 1)
    assert_eq(
      if query {
        query_composition_start()
      } else {
        editor_composition_start()
      },
      1,
    )
    assert_eq(input_preedit(query, "に😀"), 1)
    assert_eq(input_dom_preview(query, "Aに😀B", 2), 1)
    let geometry = if query {
      query_preedit_geometry
    } else {
      editor_preedit_geometry
    }
    assert_eq(geometry.val, Some((1, 4, 2)))
    ignore(@semantics.dispose(application.val.editor))
    assert_eq(input_dom_preview(query, "stale", 2), 0)
  }
}
