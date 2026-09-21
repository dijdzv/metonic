///|
async fn main {
  if @env.args().contains("--minimum") {
    verify_minimum_size()
    return
  }
  let model = @notes.create()
  let base = @notes_application.create(model)
  let started = Ref(false)
  let cleaned = Ref(false)
  let stopped = Ref(false)
  let disposed = Ref(0)
  let waiting = @async.CondVar::Cond()
  let activations = Ref(0)
  let app = {
    ..base,
    activate: reference => {
      activations.val += 1
      (base.activate)(reference)
    },
    initialize: () => {
      Some({
        request: @task.replace(() => (), () => {
          Some(
            @task.work(
              () => {
                started.val = true
                defer {
                  cleaned.val = true
                }
                waiting.wait()
                ()
              },
              _ => @task.Unchanged,
            ),
          )
        }),
        gate: Always,
      })
    },
    stop: () => {
      stopped.val = true
      (base.stop)()
    },
    dispose: () => {
      assert_true(stopped.val)
      assert_true(cleaned.val)
      @async.sleep(1)
      disposed.val += 1
    },
  }
  let completed = Ref(false)
  @window_host.run(
    app,
    font_path=@env.args().get(1),
    hidden=true,
    minimum_size=Some((320, 240)),
    controller=Some(handle => {
      @async.with_timeout(15000, async fn() {
        assert_eq((app.view)().rectangle, None)
        assert_eq(@semantics.snapshot(model.editor).length(), 2)
        let state = (handle.inspect)()
        assert_eq(state.text, "A small independent application")
        assert_true(state.frames > 0)
        while !started.val {
          @async.sleep(1)
        }
        verify_disabled_pointer(model, handle, activations)
        verify_drag_selection(model, handle, activations)
        let current = (handle.inspect)()
        assert_eq(current.controls.length(), 2)
        assert_eq(
          (handle.operate)(
            model.note,
            @window_host.InsertText("ignored"),
            current.semantic_revision - 1,
          ),
          "stale_revision",
        )
        assert_eq(
          (handle.operate)(
            { ..model.note, generation: model.note.generation + 1, },
            @window_host.InsertText("ignored"),
            current.semantic_revision,
          ),
          "stale_target",
        )
        assert_eq((handle.inspect)().text, current.text)
        assert_eq(
          (handle.operate)(
            model.note,
            @window_host.ActivateControl,
            current.semantic_revision,
          ),
          "unsupported_action",
        )
        assert_eq(@semantics.set_enabled(model.editor, model.clear, false), "")
        assert_eq(
          (handle.operate)(
            model.clear,
            @window_host.ActivateControl,
            (handle.inspect)().semantic_revision,
          ),
          "disabled",
        )
        assert_eq(@semantics.set_enabled(model.editor, model.clear, true), "")
        assert_eq(
          (handle.operate)(
            model.note,
            @window_host.SelectRange(0, current.text.length()),
            (handle.inspect)().semantic_revision,
          ),
          "",
        )
        assert_eq(
          (handle.operate)(
            model.note,
            @window_host.InsertText("targeted 日本語"),
            (handle.inspect)().semantic_revision,
          ),
          "",
        )
        assert_eq((handle.inspect)().text, "targeted 日本語")
        let before_activation = activations.val
        assert_eq(
          (handle.operate)(
            model.clear,
            @window_host.ActivateControl,
            (handle.inspect)().semantic_revision,
          ),
          "",
        )
        assert_eq(activations.val, before_activation + 1)
        assert_eq((handle.inspect)().text, "")
        assert_eq((handle.edit)(Some(state.text), None), "")
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
  assert_eq(disposed.val, 1)
  assert_eq(@semantics.set_text(model.editor, model.note, "late"), "closed")
  println("NOTES_HOST_OK")
}
