///|
test "both input fields track valid composition cursors without committing preview text" {
  fn send(text : String) -> Unit raise {
    assert_eq(text_begin(text.length()), 1)
    for index in 0..<text.length() {
      assert_eq(text_put(text.code_unit_at(index).to_int()), 1)
    }
  }
  for query in [false, true] {
    reset_state()
    let model = application.val
    let reference = if query {
      model.query_input
    } else {
      @semantics.snapshot(model.editor)[1].reference
    }
    assert_eq(@semantics.set_text(model.editor, reference, "AB"), "")
    assert_eq(@semantics.set_selection(model.editor, reference, 1, 1), "")
    assert_eq(
      if query {
        query_composition_start()
      } else {
        editor_composition_start()
      },
      1,
    )
    send("に😀")
    assert_eq(
      if query {
        query_composition_update()
      } else {
        editor_composition_update()
      },
      1,
    )
    let geometry = if query {
      query_preedit_geometry
    } else {
      editor_preedit_geometry
    }
    assert_eq(geometry.val, Some((1, 4, 4)))
    send("Aに😀B")
    assert_eq(composition_cursor(query, 2), 1)
    assert_eq(geometry.val, Some((1, 4, 2)))
    for
      entry in [("AB", 1), ("Aに😀B", 3), ("Aに😀B", 0), ("Aに😀B", 5)] {
      send(entry.0)
      assert_eq(composition_cursor(query, entry.1), 0)
      assert_eq(geometry.val, Some((1, 4, 2)))
    }
    assert_eq(
      if query {
        model.query()
      } else {
        @semantics.snapshot(model.editor)[1].value
      },
      "AB",
    )
    if query {
      query_composition_end()
    } else {
      editor_composition_end()
    }
    assert_eq(geometry.val, None)
    send("Aに😀B")
    assert_eq(composition_cursor(query, 2), 0)
  }
}
