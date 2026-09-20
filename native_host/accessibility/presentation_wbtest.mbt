///|
fn test_presentation(nodes : Array[@semantics.Node]) -> Presentation {
  {
    title: "Independent notes",
    width: 480,
    height: 320,
    controls: nodes.map(node => {
      reference: node.reference,
      bounds: { x: node.reference.id * 40, y: 20, width: 120, height: 64, },
      toggled: None,
    }),
    statuses: [
      {
        id: 2147483648UL,
        text: "Saved",
        bounds: { x: 0, y: 200, width: 160, height: 32, },
      },
    ],
    text_owner: Some(nodes[0].reference),
    composing: false,
    text_scroll: 0,
  }
}

///|
test "presentation follows exact references rather than P0 input and toggle IDs" {
  let tree = @semantics.empty(4, 7)
  let input = @semantics.add_input(tree, "Notes", "ABC").unwrap()
  ignore(@semantics.add_button(tree, "Save"))
  let nodes = @semantics.snapshot(tree)
  let presentation = test_presentation(nodes)
  assert_eq(input.id, 1)
  assert_true(valid_presentation(nodes, presentation))
  assert_true(
    valid_presentation(nodes, {
      ..presentation,
      controls: [presentation.controls[1], presentation.controls[0]],
    }),
  )
  assert_false(
    valid_presentation(nodes, {
      ..presentation,
      controls: [presentation.controls[0], presentation.controls[0]],
    }),
  )
  assert_false(
    valid_presentation(nodes, {
      ..presentation,
      text_owner: Some(nodes[1].reference),
    }),
  )
  assert_false(
    valid_presentation(nodes, {
      ..presentation,
      statuses: [{ ..presentation.statuses[0], id: 4294967296UL, }],
    }),
  )
  assert_eq(@semantics.remove(tree, input), "")
  ignore(@semantics.restore_input(tree, input.id, "Replacement", "ABC"))
  assert_false(valid_presentation(@semantics.snapshot(tree), presentation))
}

///|
async test "retained text identity preserves stable ranges and rejects replaced owners" {
  let tree = @semantics.empty(8, 9)
  let first = @semantics.add_input(tree, "Title", "ABC").unwrap()
  ignore(@semantics.add_button(tree, "Save"))
  let second = @semantics.add_input(tree, "Body", "ABC").unwrap()
  let nodes = @semantics.snapshot(tree)
  let presentation = test_presentation(nodes)
  let bridge : Bridge = {
    adapter: 0UL,
    presentation,
    nodes: [],
    fragments: [],
    layout: None,
    next_text_id: 4294967296UL,
  }
  let engine = @raster.create(
    @fs.read_file(@env.get_env_var("METONIC_RENDER_TEST_FONT").unwrap()).binary(),
  ).unwrap()
  ignore(@raster.render(engine, "ABC", 120, 64))
  let layout = @raster.text_runs(engine, "ABC").unwrap()
  assert_true(bridge.replace_snapshot(nodes, presentation, Some(layout)))
  let original = bridge.fragments[0].id
  assert_eq(bridge.text_position(1), Some((original, 1UL)))
  assert_true(
    bridge.replace_snapshot(
      nodes,
      { ..presentation, text_scroll: 12, },
      Some(layout),
    ),
  )
  assert_eq(bridge.fragments[0].id, original)
  assert_true(
    bridge.replace_snapshot(
      nodes,
      { ..presentation, text_owner: Some(second), },
      Some(layout),
    ),
  )
  let replacement = bridge.fragments[0].id
  assert_true(original != replacement)
  assert_eq(bridge.text_offset(original, 1UL), None)
  assert_eq(bridge.text_offset(replacement, 1UL), Some(1))
  let cells = layout[0].cells.unwrap()
  let cell_count = cells.length()
  assert_true(cell_count > 0)
  cells.clear()
  assert_eq(bridge.fragments[0].layout.cells.unwrap().length(), cell_count)
  assert_eq(@semantics.set_text(tree, second, "X"), "")
  assert_false(
    bridge.replace_snapshot(
      @semantics.snapshot(tree),
      { ..presentation, text_owner: Some(second), },
      Some(layout),
    ),
  )
  assert_eq(bridge.presentation.text_owner, Some(second))
  assert_eq(bridge.fragments[0].id, replacement)
  assert_true(
    bridge.replace_snapshot(
      nodes,
      { ..presentation, text_owner: Some(first), },
      None,
    ),
  )
  assert_eq(bridge.text_offset(replacement, 1UL), None)
  presentation.controls.clear()
  assert_eq(bridge.presentation.controls.length(), 3)
}
