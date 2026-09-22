///|
async fn verify_edits() -> Unit {
  let model = @notes.create()
  let edits : Array[@portable.TextEdit] = []
  let finished = Ref(0)
  let observed : Ref[@window_host.Observation?] = Ref(None)
  let clipboard = ClipboardFixture::new()
  let base = @notes_application.create(model)
  let app = {
    ..base,
    edited: edit => {
      edits.push(edit)
      Some({
        request: @task.replace(
          () => (),
          () => {
            Some(
              @task.work(() => (), _ => {
                finished.val += 1
                @task.Unchanged
              }),
            )
          },
          operation=@task.Operation::new(),
        ),
        gate: Always,
      })
    },
  }
  @window_host.run(
    app,
    hidden=true,
    clipboard=Some(clipboard.backend()),
    observer=Some(state => observed.val = Some(state)),
    controller=Some(handle => {
      @async.with_timeout(10000, () => {
        while observed.val is None {
          @async.sleep(1)
        }
        let observe = observed.val.unwrap()
        let barrier = () => drag_barrier(handle)
        let set = (text : String) => {
          assert_eq((observe.set_text)(model.note, text), "")
          (observe.draw)()
        }
        let expect = (count : Int, text : String) => {
          barrier()
          assert_eq(edits.length(), count)
          assert_eq(edits[count - 1].target, model.note)
          assert_eq(edits[count - 1].text, text)
          assert_true(
            edits[count - 1].revision <= @semantics.revision(model.editor),
          )
        }
        set("abc")
        assert_eq((handle.select)(0, 1, None), "")
        barrier()
        assert_eq(edits.length(), 0)
        (handle.apply)(Insert("X"))
        expect(1, "Xbc")
        assert_eq((handle.edit)(Some("Y"), None), "")
        expect(2, "XYbc")
        assert_eq(
          (handle.operate)(
            model.note,
            DeleteBackward,
            @semantics.revision(model.editor),
          ),
          "",
        )
        expect(3, "Xbc")
        (observe.inject)(AccessibilityValue(model.note.id, "a11y"))
        expect(4, "a11y")
        clipboard.value = Some("paste")
        assert_eq((handle.select)(0, 4, None), "")
        clipboard_key(notes_window(), 0x56UL, handle)
        expect(5, "paste")
        set("あいう")
        assert_eq((handle.select)(0, 2, None), "")
        (observe.inject)(CompositionStart)
        (observe.inject)(CompositionUpdate("青", Some(1)))
        barrier()
        assert_eq(edits.length(), 5)
        (observe.inject)(CompositionCancel)
        expect(6, "う")
        (observe.inject)(CompositionEnd)
        barrier()
        assert_eq(edits.length(), 6)
        set("あいう")
        assert_eq((handle.select)(0, 2, None), "")
        (observe.inject)(CompositionStart)
        (observe.inject)(CompositionUpdate("青", Some(1)))
        barrier()
        assert_eq(
          @semantics.set_name(model.editor, model.clear, "Updated action"),
          "",
        )
        (handle.apply)(Insert("青"))
        expect(7, "青う")
        (observe.inject)(CompositionEnd)
        barrier()
        assert_eq(edits.length(), 7)
        (observe.inject)(CompositionStart)
        (observe.inject)(CompositionUpdate("古", Some(1)))
        barrier()
        set("programmatic")
        (observe.inject)(CompositionEnd)
        barrier()
        assert_eq(edits.length(), 7)
        while finished.val < 7 {
          @async.sleep(1)
        }
        (handle.apply)(Close)
      })
    }),
  )
  assert_eq(edits.length(), 7)
  println("COMMITTED_EDIT_NATIVE_OK")
}
