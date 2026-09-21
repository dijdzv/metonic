///|
#borrow(state)
extern "C" fn keyboard_get(state : FixedArray[Byte]) -> Int = "GetKeyboardState"

///|
#borrow(state)
extern "C" fn keyboard_set(state : FixedArray[Byte]) -> Int = "SetKeyboardState"

///|
priv struct ClipboardFixture {
  mut value : String?
  mut failure : String?
  mut error : String?
  mut writes : Int
  mut reads : Int
}

///|
fn ClipboardFixture::new() -> ClipboardFixture {
  { value: None, failure: None, error: None, writes: 0, reads: 0, }
}

///|
fn ClipboardFixture::backend(self : ClipboardFixture) -> @clipboard.Backend {
  {
    read: () => {
      self.reads += 1
      match self.failure {
        Some(error) => Err(error)
        None => Ok(self.value)
      }
    },
    write: value => {
      self.writes += 1
      match self.failure {
        Some(error) => Err(error)
        None => {
          self.value = Some(value)
          Ok(())
        }
      }
    },
  }
}

///|
async fn clipboard_key(
  window : UInt64,
  key : UInt64,
  handle : @window_host.Handle,
) -> Unit {
  let delivered = (handle.inspect)().input.key_presses
  let original = FixedArray::make(256, b'\x00')
  assert_true(keyboard_get(original) != 0)
  let pressed = FixedArray::make(256, b'\x00')
  for index in 0..<256 {
    pressed[index] = original[index]
  }
  pressed[0x11] = b'\x80'
  assert_true(keyboard_set(pressed) != 0)
  defer ignore(keyboard_set(original))
  ignore(drag_send(window, 0x100U, 0x11UL, 0L))
  ignore(drag_send(window, 0x100U, key, 0L))
  ignore(drag_send(window, 0x101U, key, 0L))
  assert_true(keyboard_set(original) != 0)
  ignore(drag_send(window, 0x101U, 0x11UL, 0L))
  // A development capture alone can overtake the native window-event queue.
  @async.with_timeout(2000, async fn() {
    while (handle.inspect)().input.key_presses < delivered + 2 {
      @async.sleep(1)
    }
  })
  drag_barrier(handle)
}

///|
async fn verify_clipboard(
  model : @notes.Model,
  handle : @window_host.Handle,
  fixture : ClipboardFixture,
) -> Unit {
  let original = (handle.inspect)().text
  let window = notes_window()
  assert_eq(@semantics.focus(model.editor, model.note), "")
  drag_set_text(handle, "A😀日本B")
  assert_eq((handle.select)(1, 5, None), "")
  clipboard_key(window, 0x43UL, handle)
  assert_eq(fixture.value, Some("😀日本"))
  assert_eq((handle.inspect)().text, "A😀日本B")
  assert_eq(fixture.writes, 1)
  fixture.failure = Some("clipboard busy")
  clipboard_key(window, 0x58UL, handle)
  assert_eq((handle.inspect)().text, "A😀日本B")
  assert_eq((handle.inspect)().selection_start, 1)
  assert_eq((handle.inspect)().selection_end, 5)
  assert_eq(fixture.error, Some("Clipboard: clipboard busy"))
  fixture.failure = None
  clipboard_key(window, 0x58UL, handle)
  assert_eq((handle.inspect)().text, "AB")
  assert_eq(fixture.error, None)
  fixture.value = Some("日本\r\n😀")
  clipboard_key(window, 0x56UL, handle)
  assert_eq((handle.inspect)().text, "A日本\n😀B")
  assert_eq(fixture.reads, 1)
  drag_set_text(handle, original)
  println(
    "NOTES_CLIPBOARD_KEYS_OK copy cut_failure_preserved cut paste unicode error_notification fake_backend",
  )
}
