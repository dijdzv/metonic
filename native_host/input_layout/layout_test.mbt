///|
async test "input layouts retain independent geometry and scroll without sample identities" {
  let font = @fs.read_file(
    @env.get_env_var("METONIC_RENDER_TEST_FONT").unwrap(),
  ).binary()
  let tree = @semantics.empty(5, 3)
  let first = @semantics.add_input(tree, "Title", "").unwrap()
  let second = @semantics.add_input(tree, "Filter", "").unwrap()
  let multiline = @semantics.add_input(tree, "Notes", "").unwrap()
  let layouts = create(tree)
  assert_true(layouts.register(first, font, true))
  assert_true(layouts.register(second, font, true))
  assert_true(layouts.register(multiline, font, false))
  assert_false(layouts.register(first, font, true))
  let long_text = "abc def ghi jkl mno pqr stu"
  assert_true(
    layouts.prepare_single_line(first, long_text, 40, Some(long_text.length())),
  )
  assert_true(layouts.scroll_x(first) > 0)
  assert_eq(layouts.scroll_x(second), 0)
  let first_end = @raster.caret_position(
    layouts.engine(first).unwrap(),
    long_text.length(),
  )
  assert_true(layouts.prepare_single_line(second, "abc", 80, Some(0)))
  assert_eq(
    @raster.caret_position(layouts.engine(first).unwrap(), long_text.length()),
    first_end,
  )
  assert_true(layouts.prepare_single_line(first, "a", 40, None))
  assert_eq(layouts.scroll_x(first), 0)
  assert_false(layouts.prepare_single_line(multiline, "abc", 40, None))
  assert_false(layouts.prepare_single_line(first, "abc", 1025, None))
  let text = "one\ntwo\nthree\nfour\nfive"
  ignore(
    @raster.render(
      layouts.engine(multiline).unwrap(),
      text,
      120,
      64,
      follow_caret=Some(text.length()),
    ),
  )
  assert_true(layouts.sync_vertical_scroll(multiline))
  assert_true(layouts.scroll_y(multiline) > 0)
  assert_eq(layouts.scroll_y(first), 0)
  assert_false(layouts.sync_vertical_scroll(first))
}

///|
async test "input removal replacement and disposal reject old layout handles" {
  let font = @fs.read_file(
    @env.get_env_var("METONIC_RENDER_TEST_FONT").unwrap(),
  ).binary()
  let tree = @semantics.empty(5, 3)
  let input = @semantics.add_input(tree, "Title", "").unwrap()
  let button = @semantics.add_button(tree, "Save").unwrap()
  let layouts = create(tree)
  assert_false(layouts.register(button, font, true))
  let foreign_tree = @semantics.empty(6, 3)
  let foreign = @semantics.add_input(foreign_tree, "Title", "").unwrap()
  assert_false(layouts.register(foreign, font, true))
  assert_true(layouts.register(input, font, true))
  assert_eq(@semantics.remove(tree, input), "")
  assert_true(layouts.engine(input) is None)
  assert_false(layouts.prepare_single_line(input, "late", 40, Some(4)))
  let fresh = @semantics.restore_input(tree, input.id, "Replacement", "").unwrap()
  assert_true(layouts.engine(fresh) is None)
  assert_false(layouts.register(input, font, true))
  assert_true(layouts.register(fresh, font, false))
  assert_eq(layouts.scroll_x(fresh), 0)
  layouts.remove(fresh)
  assert_true(layouts.engine(fresh) is None)
  assert_true(layouts.register(fresh, font, false))
  assert_true(@semantics.dispose(tree))
  assert_true(layouts.engine(fresh) is None)
  assert_false(layouts.sync_vertical_scroll(fresh))
  layouts.clear()
}
