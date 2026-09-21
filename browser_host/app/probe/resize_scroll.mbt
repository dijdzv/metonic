///|
fn resize_editor(height : Int) -> Unit {
  @dom_view.place(@dom_view.element("app"), [
    {
      element: @dom_view.element("text-input"),
      bounds: { x: 0, y: 0, width: 200, height, },
      class_name: None,
    },
  ])
}

///|
fn check_resize_scroll(editor : @dom.HTMLTextAreaElement) -> Unit raise {
  let element = @input_binding.Multiline(editor)
  let text = "one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\nten"
  editor.set_value(text)
  focus_editor(editor)
  select_editor(
    editor,
    text.length().reinterpret_as_uint(),
    text.length().reinterpret_as_uint(),
  )
  resize_editor(96)
  let before = element.restore_scroll((0, true))
  assert_true(before > 0)
  let state = element.capture_scroll()
  assert_true(state.1)
  resize_editor(32)
  assert_true(element.restore_scroll(state) > before)
  assert_true(element.capture_scroll().1)
  assert_eq(element.value(), text)
  assert_eq(element.restore_scroll((10, false)), 10)
  let reading = element.capture_scroll()
  assert_false(reading.1)
  resize_editor(64)
  assert_eq(element.restore_scroll(reading), 10)
  resize_editor(1024)
  ignore(element.restore_scroll((0, false)))
  let end_without_overflow = element.capture_scroll()
  assert_true(end_without_overflow.1)
  resize_editor(32)
  assert_true(element.restore_scroll(end_without_overflow) > 0)
  resize_editor(1024)
  select_editor(editor, 0U, 0U)
  ignore(element.restore_scroll((0, false)))
  let start = element.capture_scroll()
  assert_false(start.1)
  resize_editor(96)
  assert_eq(element.restore_scroll(start), 0)
}
