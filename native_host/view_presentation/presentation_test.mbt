///|
async test "independent input items retain layout and unchanged frames reuse their pixels" {
  let font = @fs.read_file(
    @env.get_env_var("METONIC_RENDER_TEST_FONT").unwrap(),
  ).binary()
  let tree = @semantics.empty(4, 8)
  let first = @semantics.add_input(tree, "Filter", "abc def ghi jkl").unwrap()
  let second = @semantics.add_input(tree, "Notes", "one\ntwo\nthree\nfour").unwrap()
  let layouts = @layout.create(tree)
  let presenter = create(tree, layouts, @navigation.create(tree), font).unwrap()
  let items = [
    @renderer.item({
      bounds: { x: 10, y: 80, width: 120, height: 64, },
      text: "",
      reference: Some(second),
      focused: false,
    }),
    @renderer.item(
      {
        bounds: { x: 10, y: 10, width: 80, height: 32, },
        text: "",
        reference: Some(first),
        focused: false,
      },
      surface=Control,
    ),
  ]
  let inputs : Array[Input] = [
    { reference: first, single_line: true, },
    { reference: second, single_line: false, },
  ]
  let initial = presenter.render(items, inputs, None).unwrap().unwrap()
  assert_eq(initial.length(), 2)
  assert_eq(presenter.input_width(first), Some(64))
  assert_eq(presenter.input_width(second), Some(120))
  assert_eq(presenter.hit_input(first, 18, 12).unwrap().0, 0)
  assert_eq(
    presenter.hit_input(second, 10, 80),
    @raster.hit_caret(
      layouts.engine(second).unwrap(),
      0,
      layouts.scroll_y(second),
    ),
  )
  assert_eq(
    presenter.hit_input(first, 18, 12),
    @raster.hit_caret(layouts.engine(first).unwrap(), 0, 0),
  )
  assert_eq(initial[0].bounds, items[0].element.bounds)
  assert_true(presenter.render(items, inputs, None).unwrap() is None)
  assert_eq(@semantics.focus(tree, first), "")
  let end = @semantics.node(tree, first).unwrap().value.length()
  assert_eq(@semantics.set_selection_directed(tree, first, end, end), "")
  assert_true(presenter.render(items, inputs, None).unwrap() is Some(_))
  assert_true(layouts.scroll_x(first) > 0)
  assert_eq(layouts.scroll_x(second), 0)
  assert_true(presenter.render(items, inputs, None).unwrap() is None)
  assert_eq(@semantics.focus(tree, second), "")
  let end = @semantics.node(tree, second).unwrap().value.length()
  assert_eq(@semantics.set_selection_directed(tree, second, end, end), "")
  assert_true(presenter.render(items, inputs, None).unwrap() is Some(_))
  assert_true(layouts.scroll_y(second) > 0)
  assert_true(presenter.render(items, inputs, None).unwrap() is None)
  assert_true(
    @raster.matches_layout(
      layouts.engine(first).unwrap(),
      "abc def ghi jkl",
      64,
      true,
    ),
  )
  assert_true(
    @raster.matches_layout(
      layouts.engine(second).unwrap(),
      "one\ntwo\nthree\nfour",
      120,
      false,
    ),
  )
}

///|
async test "invalid presentation references are rejected before replacing retained input layout" {
  let font = @fs.read_file(
    @env.get_env_var("METONIC_RENDER_TEST_FONT").unwrap(),
  ).binary()
  let tree = @semantics.empty(4, 8)
  let reference = @semantics.add_input(tree, "Draft", "abc").unwrap()
  let layouts = @layout.create(tree)
  let presenter = create(tree, layouts, @navigation.create(tree), font).unwrap()
  let item = @renderer.item({
    bounds: { x: 0, y: 0, width: 120, height: 64, },
    text: "",
    reference: Some(reference),
    focused: false,
  })
  let input = Input::{ reference, single_line: false, }
  ignore(presenter.render([item], [input], None).unwrap())
  assert_true(
    presenter.render(
      [item],
      [input],
      Some({ reference, text: "a", cursor: 2, ranges: [], }),
    )
    is Err("invalid_preedit_cursor"),
  )
  assert_true(
    presenter.render(
      [item],
      [input],
      Some({ reference, text: "a", cursor: 1, ranges: [(0, 2)], }),
    )
    is Err("invalid_preedit_range"),
  )
  assert_true(
    presenter.render([item], [input, input], None) is Err("duplicate_input"),
  )
  assert_true(presenter.render([item], [], None) is Err("input_mode_missing"))
  assert_true(presenter.render([], [input], None) is Err("input_item_count"))
  assert_true(
    @raster.matches_layout(
      layouts.engine(reference).unwrap(),
      "abc",
      120,
      false,
    ),
  )
  assert_eq(@semantics.remove(tree, reference), "")
  assert_eq(presenter.input_width(reference), None)
  assert_true(presenter.render([item], [input], None) is Err("stale_target"))
}
