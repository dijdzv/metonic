///|
async fn main {
  let model = @notes.create()
  let app = @notes_application.create(model)
  let completed = Ref(false)
  @window_host.run(
    app,
    hidden=true,
    controller=Some(handle => {
      @async.with_timeout(15000, async fn() {
        assert_eq((app.view)().rectangle, None)
        assert_eq(@semantics.snapshot(model.editor).length(), 2)
        let state = (handle.inspect)()
        assert_eq(state.text, "A small independent application")
        assert_true(state.frames > 0)
        assert_eq((handle.select)(0, state.text.length(), None), "")
        assert_eq((handle.edit)(Some("Notes 日本語\nsecond line"), None), "")
        assert_eq((handle.inspect)().text, "Notes 日本語\nsecond line")
        let captured_revision = Ref(-1)
        let capture = (handle.capture)(state => {
          captured_revision.val = state.semantic_revision
        })
        assert_eq(captured_revision.val, capture.state.semantic_revision)
        assert_eq(capture.width, 480)
        assert_eq(capture.height, 240)
        assert_eq(capture.pixels.length(), 480 * 240 * 4)
        assert_eq(@semantics.focus(model.editor, model.clear), "")
        (handle.apply)(@window_host.Activate)
        assert_eq((handle.inspect)().text, "")
        completed.val = true
        (handle.apply)(@window_host.Close)
      })
    }),
  )
  assert_true(completed.val)
  assert_eq(@semantics.set_text(model.editor, model.note, "late"), "closed")
  println("NOTES_HOST_OK")
}
