///|
async fn main {
  let stored : Ref[String?] = Ref(Some("External memo 日本語"))
  let application = @model.create_collection(
    {
      load: () => Ok(stored.val),
      save: value => {
        stored.val = Some(value)
        Ok(())
      },
    },
    () => (),
  )
  let completed = Ref(false)
  @window_host.run(
    minimum_size=Some((320, 360)),
    @host.from_application(application),
    hidden=true,
    controller=Some(handle => {
      @async.with_timeout(15000, async fn() {
        @clock_probe.verify()
        while (application.view)().last().unwrap().element.text == "Loading..." {
          @async.sleep(1)
        }
        let before = (handle.inspect)()
        assert_eq(before.text, "External memo 日本語")
        assert_true(before.frames > 0)
        assert_eq(
          @semantics.focus(application.editor, application.default_input.unwrap()),
          "",
        )
        let before_frame = (handle.capture)(_ => ())
        (application.input_error)(Some("Clipboard: unavailable"))
        assert_eq(
          (application.view)().last().unwrap().element.text,
          "Saved | Clipboard: unavailable",
        )
        assert_eq(
          (handle.select)(before.selection_start, before.selection_end, None),
          "",
        )
        let error_frame = (handle.capture)(_ => ())
        assert_false(
          error_frame.pixels == before_frame.pixels,
          msg="input failure was not rendered",
        )
        assert_eq((handle.inspect)().text, before.text)
        (application.input_error)(None)
        assert_eq((application.view)().last().unwrap().element.text, "Saved")
        let long_text = Array::makei(18, i => {
          "日本語の行 " + (i + 1).to_string()
        }).join("\n")
        assert_eq((handle.select)(0, before.text.length(), None), "")
        assert_eq((handle.edit)(Some(long_text), None), "")
        assert_eq((handle.inspect)().text, long_text)
        let frame = (handle.capture)(_ => ())
        assert_eq(frame.width, 760)
        assert_eq(frame.height, 520)
        assert_eq(frame.pixels.length(), 760 * 520 * 4)
        assert_false(
          frame.pixels == before_frame.pixels,
          msg="editing did not change rendered pixels",
        )
        for (width, height) in [(320, 360), (480, 400), (760, 520), (1200, 900)] {
          (handle.apply)(@window_host.Resize(width, height))
          while (handle.inspect)().width != width ||
                (handle.inspect)().height != height {
            @async.sleep(1)
          }
          let resized = (handle.capture)(_ => ())
          assert_eq(resized.width, width)
          assert_eq(resized.height, height)
          let state = (handle.inspect)()
          assert_eq(state.text, long_text)
          let bounds = (application.view)()[0].element.bounds
          let caret_y = state.ime_requested_y.unwrap()
          assert_true(
            caret_y >= bounds.y && caret_y + 32 <= bounds.y + bounds.height,
          )
          assert_true(
            @semantics.node(application.editor, application.default_input.unwrap()).unwrap().focused,
          )
        }
        @async.with_timeout(3000, () => {
          while @collection.decode(stored.val).unwrap().items()[0].text != long_text {
            @async.sleep(1)
          }
          while !(application.can_close)() { @async.sleep(1) }
        })
        assert_true((application.can_close)())
        assert_eq((handle.select)(long_text.length(), long_text.length(), None), "")
        assert_eq((handle.edit)(Some("\nsearch proof"), None), "")
        let long_text = long_text + "\nsearch proof"
        let query = (application.view)().iter().find_first(control => {
          control.element.reference is Some(reference) &&
          @semantics.node(application.editor, reference).unwrap().name == "Search memos"
        }).unwrap().element.reference.unwrap()
        let rows = () => (application.view)().filter(control => control.kind is Button && control.element.text.contains("Memo ")).length()
        assert_eq((handle.operate)(query, @window_host.InsertText("no-match"), @semantics.revision(application.editor)), "")
        while rows() != 0 { @async.sleep(1) }
        assert_eq((handle.inspect)().text, long_text)
        assert_eq((handle.operate)(query, @window_host.SelectRange(0, 8), @semantics.revision(application.editor)), "")
        assert_eq((handle.operate)(query, @window_host.InsertText(""), @semantics.revision(application.editor)), "")
        while rows() != 1 { @async.sleep(1) }
        @async.with_timeout(3000, () => {
          while @collection.decode(stored.val).unwrap().items()[0].text != long_text {
            @async.sleep(1)
          }
        })
        (handle.apply)(@window_host.Resize(100, 100))
        while (handle.inspect)().width != 320 ||
              (handle.inspect)().height != 360 {
          @async.sleep(1)
        }
        assert_eq((handle.inspect)().text, long_text)
        let minimum_frame = (handle.capture)(_ => ())
        assert_eq((minimum_frame.width, minimum_frame.height), (320, 360))
        assert_eq((handle.select)(0, long_text.length(), None), "")
        assert_eq((handle.edit)(Some(long_text + "\nclose draft"), None), "")
        assert_false((application.can_close)())
        (handle.apply)(@window_host.Close)
        assert_eq((application.view)()[3].element.text, "Cancel")
        assert_false(@semantics.node(application.editor, application.default_input.unwrap()).unwrap().enabled)
        assert_eq(
          @semantics.focus(
            application.editor,
            (application.view)()[1].element.reference.unwrap(),
          ),
          "",
        )
        completed.val = true
        (handle.apply)(@window_host.Activate)
      })
    }),
  )
  assert_true(completed.val)
  assert_eq(@collection.decode(stored.val).unwrap().items()[0].text, Array::makei(18, i => "日本語の行 " + (i + 1).to_string()).join("\n") + "\nsearch proof\nclose draft")
  assert_eq(
    @semantics.set_text(application.editor, application.default_input.unwrap(), "late"),
    "closed",
  )
  println("EXTERNAL_NOTES_NATIVE_OK")
}
