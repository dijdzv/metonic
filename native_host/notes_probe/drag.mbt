///|
extern "C" fn drag_send(
  window : UInt64,
  message : UInt,
  keys : UInt64,
  point : Int64,
) -> Int64 = "SendMessageW"

///|
fn drag_message(
  window : UInt64,
  message : UInt,
  keys : UInt64,
  x : Int,
  y : Int,
) -> Unit {
  ignore(
    drag_send(window, message, keys, ((y << 16) | (x & 0xFFFF)).to_int64()),
  )
}

///|
async fn drag_set_text(handle : @window_host.Handle, text : String) -> Unit {
  assert_eq((handle.select)(0, (handle.inspect)().text.length(), None), "")
  assert_eq((handle.edit)(Some(text), None), "")
  assert_eq((handle.select)(0, 0, None), "")
}

///|
async fn drag_barrier(handle : @window_host.Handle) -> Unit {
  ignore((handle.capture)(_ => ()))
}

///|
async fn verify_drag_selection(
  model : @notes.Model,
  handle : @window_host.Handle,
  activations : Ref[Int],
) -> Unit {
  let window = notes_window()
  let original = (handle.inspect)().text
  let text = "A😀BC"
  assert_eq(@semantics.focus(model.editor, model.note), "")
  drag_set_text(handle, text)
  drag_message(window, 0x201U, 1UL, 17, 20)
  drag_message(window, 0x200U, 1UL, 440, 20)
  drag_message(window, 0x202U, 0UL, 440, 20)
  drag_barrier(handle)
  let forward = @semantics.node(model.editor, model.note).unwrap()
  assert_eq(
    (forward.selection_start, forward.selection_end),
    (0, text.length()),
  )
  assert_eq(forward.selection_anchor, 0)
  assert_eq((handle.edit)(Some("か"), None), "")
  assert_eq((handle.inspect)().text, "か")

  drag_set_text(handle, text)
  drag_message(window, 0x201U, 1UL, 440, 20)
  drag_message(window, 0x200U, 1UL, 17, 20)
  drag_message(window, 0x202U, 0UL, 17, 20)
  drag_barrier(handle)
  let backward = @semantics.node(model.editor, model.note).unwrap()
  assert_eq(
    (backward.selection_start, backward.selection_end),
    (0, text.length()),
  )
  assert_eq(backward.selection_anchor, text.length())

  drag_set_text(handle, text)
  drag_message(window, 0x201U, 1UL, 17, 20)
  drag_message(window, 0x200U, 1UL, 17, 20)
  drag_message(window, 0x202U, 0UL, 440, 20)
  drag_barrier(handle)
  let released = @semantics.node(model.editor, model.note).unwrap()
  assert_eq(
    (released.selection_start, released.selection_end),
    (0, text.length()),
  )

  drag_set_text(handle, text)
  let previous_activations = activations.val
  drag_message(window, 0x201U, 1UL, 17, 20)
  drag_message(window, 0x200U, 1UL, 60, 144)
  drag_message(window, 0x202U, 0UL, 60, 144)
  drag_barrier(handle)
  assert_eq(activations.val, previous_activations)
  assert_eq((handle.inspect)().text, text)

  drag_set_text(handle, text)
  drag_message(window, 0x201U, 1UL, 17, 20)
  drag_message(window, 0x200U, 1UL, 440, 20)
  drag_barrier(handle)
  ignore(drag_send(window, 0x1FU, 0UL, 0L))
  drag_message(window, 0x200U, 0UL, 17, 20)
  drag_message(window, 0x202U, 0UL, 17, 20)
  drag_barrier(handle)
  let canceled = @semantics.node(model.editor, model.note).unwrap()
  assert_eq(
    (canceled.selection_start, canceled.selection_end),
    (0, text.length()),
  )

  drag_set_text(handle, text)
  drag_message(window, 0x201U, 1UL, 17, 20)
  drag_barrier(handle)
  assert_eq(@semantics.set_enabled(model.editor, model.note, false), "")
  drag_message(window, 0x200U, 1UL, 440, 20)
  drag_barrier(handle)
  assert_eq(@semantics.set_enabled(model.editor, model.note, true), "")
  drag_message(window, 0x202U, 0UL, 440, 20)
  drag_barrier(handle)
  let disabled = @semantics.node(model.editor, model.note).unwrap()
  assert_eq((disabled.selection_start, disabled.selection_end), (0, 0))

  drag_set_text(handle, text)
  drag_message(window, 0x201U, 1UL, 17, 20)
  drag_barrier(handle)
  assert_eq((handle.edit)(Some("changed"), None), "")
  let changed = @semantics.node(model.editor, model.note).unwrap()
  drag_message(window, 0x200U, 1UL, 440, 20)
  drag_message(window, 0x202U, 0UL, 440, 20)
  drag_barrier(handle)
  let after_change = @semantics.node(model.editor, model.note).unwrap()
  assert_eq(after_change.value, changed.value)
  assert_eq(
    (after_change.selection_start, after_change.selection_end),
    (changed.selection_start, changed.selection_end),
  )

  let multiline = Array::make(18, "日本語の行😀").join("\n")
  drag_set_text(handle, multiline)
  drag_message(window, 0x201U, 1UL, 17, 20)
  drag_message(window, 0x200U, 1UL, 440, 200)
  @async.with_timeout(3000, () => {
    while @semantics.node(model.editor, model.note).unwrap().selection_end !=
          multiline.length() {
      @async.sleep(10)
    }
  })
  drag_message(window, 0x202U, 0UL, 440, 200)
  drag_barrier(handle)
  let scrolled = @semantics.node(model.editor, model.note).unwrap()
  assert_eq(
    (scrolled.selection_start, scrolled.selection_end),
    (0, multiline.length()),
  )
  assert_eq(activations.val, previous_activations)
  assert_eq((handle.edit)(Some("ドラッグ置換"), None), "")
  assert_eq((handle.inspect)().text, "ドラッグ置換")
  drag_set_text(handle, original)
  println(
    "NOTES_DRAG_SELECTION_OK forward backward utf16 replace crossing_control cancel multiline_autoscroll",
  )
}
