///|
async fn verify_wheel_scroll(
  model : @notes.Model,
  handle : @window_host.Handle,
) -> Unit {
  let window = notes_window()
  assert_eq(
    (handle.edit)(Some("one\ntwo\nthree\nfour\nfive\nsix\nseven\neight"), None),
    "",
  )
  assert_eq((handle.select)(0, 0, None), "")
  let initial = (handle.capture)(_ => ())
  assert_true(
    pointer_post(window, 0x200U, 0UL, (40 * 65536 + 60).to_int64()) != 0,
  )
  let before = (handle.inspect)().frames
  assert_true(pointer_post(window, 0x20AU, 0xFF880000UL, 0L) != 0)
  @async.with_timeout(2000, () => {
    while (handle.inspect)().frames <= before {
      @async.sleep(5)
    }
  })
  let down = (handle.capture)(_ => ())
  assert_true(down.pixels != initial.pixels)
  assert_eq(down.state.text, initial.state.text)
  assert_eq(down.state.selection_start, initial.state.selection_start)
  assert_eq(down.state.selection_end, initial.state.selection_end)
  assert_eq(down.state.semantic_revision, initial.state.semantic_revision)
  let before = (handle.inspect)().frames
  // Hidden-window tracking may report pointer leave between gestures.
  assert_true(
    pointer_post(window, 0x200U, 0UL, (40 * 65536 + 60).to_int64()) != 0,
  )
  assert_true(pointer_post(window, 0x20AU, 0x00780000UL, 0L) != 0)
  @async.with_timeout(2000, () => {
    while (handle.inspect)().frames <= before {
      @async.sleep(5)
    }
  })
  let up = (handle.capture)(_ => ())
  assert_eq(up.pixels, initial.pixels)
  assert_eq(
    @semantics.node(model.editor, model.note).unwrap().value,
    initial.state.text,
  )
  println("NOTES_WHEEL_OK pixels_scrolled text_selection_preserved")
}
