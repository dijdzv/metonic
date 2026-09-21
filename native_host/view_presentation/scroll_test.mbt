///|
async test "manual viewport scroll persists across redraw and editing restores caret visibility" {
  let font = @fs.read_file(
    @env.get_env_var("METONIC_RENDER_TEST_FONT").unwrap(),
  ).binary()
  let tree = @semantics.empty(4, 8)
  let reference = @semantics.add_input(
    tree, "Memo", "one\ntwo\nthree\nfour\nfive\nsix",
  ).unwrap()
  assert_eq(@semantics.focus(tree, reference), "")
  assert_eq(@semantics.set_selection_directed(tree, reference, 0, 0), "")
  let layouts = @layout.create(tree)
  let presenter = create(tree, layouts, @navigation.create(tree), font).unwrap()
  let items = [
    @renderer.item({
      bounds: { x: 0, y: 0, width: 120, height: 64, },
      text: "",
      reference: Some(reference),
      focused: false,
    }),
  ]
  let inputs = [Input::{ reference, single_line: false, }]
  ignore(presenter.render(items, inputs, None).unwrap())
  let original = @semantics.node(tree, reference).unwrap()
  assert_true(presenter.scroll_input(reference, 64))
  assert_true(presenter.render(items, inputs, None).unwrap() is Some(_))
  assert_eq(layouts.scroll_y(reference), 64)
  assert_true(presenter.render(items, inputs, None).unwrap() is None)
  assert_eq(layouts.scroll_y(reference), 64)
  let after = @semantics.node(tree, reference).unwrap()
  assert_eq(after.value, original.value)
  assert_eq(after.selection_start, original.selection_start)
  assert_eq(after.selection_end, original.selection_end)
  assert_true(presenter.scroll_input(reference, 2147483647))
  ignore(presenter.render(items, inputs, None).unwrap())
  assert_eq(layouts.scroll_y(reference), 128)
  assert_true(presenter.scroll_input(reference, -2147483647))
  ignore(presenter.render(items, inputs, None).unwrap())
  assert_eq(layouts.scroll_y(reference), 0)
  assert_true(presenter.scroll_input(reference, 96))
  ignore(presenter.render(items, inputs, None).unwrap())
  assert_eq(layouts.scroll_y(reference), 96)
  assert_eq(@semantics.set_selection_directed(tree, reference, 1, 1), "")
  ignore(presenter.render(items, inputs, None).unwrap())
  assert_eq(layouts.scroll_y(reference), 0)
  assert_true(presenter.scroll_input(reference, 96))
  ignore(presenter.render(items, inputs, None).unwrap())
  assert_eq(layouts.scroll_y(reference), 96)
  presenter.reveal_input(reference)
  ignore(presenter.render(items, inputs, None).unwrap())
  assert_eq(layouts.scroll_y(reference), 0)
  assert_eq(@semantics.set_enabled(tree, reference, false), "")
  assert_false(presenter.scroll_input(reference, 32))
}

///|
async test "wheel viewport preserves Japanese preedit and rejects single line inputs" {
  let font = @fs.read_file(
    @env.get_env_var("METONIC_RENDER_TEST_FONT").unwrap(),
  ).binary()
  let tree = @semantics.empty(4, 8)
  let reference = @semantics.add_input(
    tree, "Memo", "一\n二\n三\n四\n五\n六",
  ).unwrap()
  let single = @semantics.add_input(tree, "ID", "123").unwrap()
  assert_eq(@semantics.focus(tree, reference), "")
  assert_eq(@semantics.set_selection_directed(tree, reference, 0, 1), "")
  let layouts = @layout.create(tree)
  let presenter = create(tree, layouts, @navigation.create(tree), font).unwrap()
  let items = [
    @renderer.item({
      bounds: { x: 0, y: 0, width: 120, height: 64, },
      text: "",
      reference: Some(reference),
      focused: false,
    }),
    @renderer.item({
      bounds: { x: 0, y: 80, width: 120, height: 32, },
      text: "",
      reference: Some(single),
      focused: false,
    }),
  ]
  let inputs = [
    Input::{ reference, single_line: false, },
    Input::{ reference: single, single_line: true, },
  ]
  let preedit = Preedit::{
    reference,
    text: "青\n二\n三\n四\n五\n六",
    cursor: 1,
    ranges: [(0, 1)],
  }
  ignore(presenter.render(items, inputs, Some(preedit)).unwrap())
  assert_false(presenter.scroll_input(single, 64))
  assert_true(presenter.scroll_input(reference, 64))
  ignore(presenter.render(items, inputs, Some(preedit)).unwrap())
  assert_eq(layouts.scroll_y(reference), 64)
  assert_eq(presenter.input_text(reference), Some(preedit.text))
  assert_eq(
    @semantics.node(tree, reference).unwrap().value,
    "一\n二\n三\n四\n五\n六",
  )
  assert_eq(@semantics.node(tree, reference).unwrap().selection_end, 1)
  assert_true(presenter.render(items, inputs, Some(preedit)).unwrap() is None)
  ignore(presenter.render(items, inputs, None).unwrap())
  assert_eq(layouts.scroll_y(reference), 0)
  assert_eq(
    presenter.input_text(reference),
    Some("一\n二\n三\n四\n五\n六"),
  )
}
