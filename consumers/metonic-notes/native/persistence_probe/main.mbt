///|
async fn main {
  let directory = @env.get_env_var("METONIC_NOTES_DATA").unwrap()
  let storage = @storage.create(directory)
  let app = @model.create_collection(storage.adapter(), () => storage.dispose())
  let restoring = @env.get_env_var("METONIC_NOTES_RESTORE") == Some("1")
  let completed = Ref(false)
  @window_host.run(
    @host.from_application(app),
    hidden=true,
    controller=Some(handle => {
      @async.with_timeout(20000, async fn() {
        let status = () => (app.view)().last().unwrap().element.text
        let activate = index => {
          assert_eq(
            @semantics.focus(
              app.editor,
              (app.view)()[index].element.reference.unwrap(),
            ),
            "",
          )
          (handle.apply)(@window_host.Activate)
        }
        let select_note = (id : Int) => {
          let reference = (app.view)()
          .iter()
          .find_first(control => {
            control.element.text.contains("Memo " + id.to_string())
          })
          .unwrap().element.reference.unwrap()
          assert_eq(@semantics.focus(app.editor, reference), "")
          (handle.apply)(@window_host.Activate)
        }
        let edit = value => {
          assert_eq(
            @semantics.focus(app.editor, app.default_input.unwrap()),
            "",
          )
          assert_eq((handle.edit)(Some(value), None), "")
        }
        while status() == "Loading..." {
          @async.sleep(1)
        }
        if !restoring {
          assert_true(status().has_prefix("Load failed:"))
          assert_false(
            @semantics.node(app.editor, app.default_input.unwrap()).unwrap().enabled,
          )
          assert_eq(@fs.read_file(directory + "/snapshot").binary(), b"\xff")
          @fs.remove(directory + "/snapshot")
          activate(1)
          while status() == "Loading..." {
            @async.sleep(1)
          }
        }
        assert_eq(status(), "Saved")
        if restoring {
          assert_eq(
            (handle.inspect)().text,
            "日本語メモ1\n保存と復元・再試行",
          )
          select_note(5)
          assert_eq(
            (handle.inspect)().text,
            "日本語メモ5\n保存と復元",
          )
          activate(4)
          assert_eq((app.view)()[4].element.text, "Confirm delete")
          assert_eq(
            (handle.inspect)().text,
            "日本語メモ5\n保存と復元",
          )
          activate(4)
          assert_true(
            (app.view)()
            .iter()
            .find_first(control => control.element.text.contains("Memo 5"))
            is None,
          )
          select_note(1)
          assert_eq(
            (handle.inspect)().text,
            "日本語メモ1\n保存と復元・再試行",
          )
          assert_false((app.can_close)())
          activate(2)
          @async.with_timeout(5000, () => {
            while status() == "Saving..." {
              @async.sleep(1)
            }
          })
          select_note(5)
          assert_eq(
            (handle.inspect)().text,
            "日本語メモ5\n保存と復元",
          )
        } else {
          assert_false(
            @semantics.node(app.editor, app.default_input.unwrap()).unwrap().enabled,
          )
          for i in 1..<6 {
            activate(3)
            edit("日本語メモ" + i.to_string() + "\n保存と復元")
          }
          activate(5)
          activate(7)
          assert_eq(
            (handle.inspect)().text,
            "日本語メモ1\n保存と復元",
          )
          @async.with_timeout(5000, () => {
            while status() == "Saving..." {
              @async.sleep(1)
            }
          })
          let snapshot_before = if @fs.exists(directory + "/snapshot") {
            Some(@fs.read_file(directory + "/snapshot").text())
          } else {
            None
          }
          @fs.mkdir(directory + "/snapshot.pending")
          assert_eq(
            (handle.select)(0, (handle.inspect)().text.length(), None),
            "",
          )
          edit("日本語メモ1\n保存と復元・再試行")
          assert_false((app.can_close)())
          (handle.apply)(@window_host.Close)
          assert_eq((app.view)()[3].element.text, "Cancel")
          activate(3)
          assert_eq(
            (handle.inspect)().text,
            "日本語メモ1\n保存と復元・再試行",
          )
          activate(1)
          @async.with_timeout(5000, () => {
            while !status().has_prefix("Save failed:") {
              @async.sleep(1)
            }
          })
          assert_true(status().has_prefix("Save failed:"))
          assert_false((app.can_close)())
          assert_eq(
            if @fs.exists(directory + "/snapshot") {
              Some(@fs.read_file(directory + "/snapshot").text())
            } else {
              None
            },
            snapshot_before,
          )
          @fs.rmdir(directory + "/snapshot.pending")
          activate(1)
          @async.with_timeout(5000, () => {
            while status() != "Saved" {
              @async.sleep(1)
            }
          })
          assert_eq(status(), "Saved")
          let query = (app.view)()
          .iter()
          .find_first(control => {
            control.element.reference is Some(reference) &&
            @semantics.node(app.editor, reference).unwrap().name ==
            "Search memos"
          })
          .unwrap().element.reference.unwrap()
          let rows = () => {
            (app.view)().filter(control => {
              control.element.text.contains("Memo ")
            })
          }
          assert_eq(
            (handle.operate)(
              query,
              @window_host.InsertText("5"),
              @semantics.revision(app.editor),
            ),
            "",
          )
          @async.with_timeout(3000, () => {
            while rows().length() != 1 {
              @async.sleep(1)
            }
          })
          assert_eq(rows()[0].element.text, "Memo 5")
          assert_eq(
            @semantics.focus(app.editor, rows()[0].element.reference.unwrap()),
            "",
          )
          (handle.apply)(@window_host.Activate)
          assert_eq(
            (handle.inspect)().text,
            "日本語メモ5\n保存と復元",
          )
          assert_eq(
            (handle.operate)(
              query,
              @window_host.SelectRange(0, 1),
              @semantics.revision(app.editor),
            ),
            "",
          )
          assert_eq(
            (handle.operate)(
              query,
              @window_host.InsertText(""),
              @semantics.revision(app.editor),
            ),
            "",
          )
          @async.with_timeout(3000, () => {
            while rows().length() != 5 {
              @async.sleep(1)
            }
          })
          activate(7)
          assert_eq(
            (handle.inspect)().text,
            "日本語メモ1\n保存と復元・再試行",
          )
          @async.with_timeout(5000, () => {
            while status() == "Saving..." {
              @async.sleep(1)
            }
          })
          assert_eq(
            (handle.select)(0, (handle.inspect)().text.length(), None),
            "",
          )
          edit("discard this edit")
          activate(2)
          @async.with_timeout(5000, () => {
            while status() == "Saving..." {
              @async.sleep(1)
            }
          })
          assert_eq(
            (handle.inspect)().text,
            "日本語メモ1\n保存と復元・再試行",
          )
        }
        assert_true((app.can_close)())
        let capture = (handle.capture)(_ => ())
        assert_eq(capture.width, 760)
        assert_eq(capture.height, 520)
        completed.val = true
        (handle.apply)(@window_host.Close)
      })
    }),
  ) catch {
    error => {
      println(error.to_string())
      abort("native collection probe failed")
    }
  }
  assert_true(completed.val)
  println(
    if restoring {
      "NOTES_COLLECTION_RESTORE_OK"
    } else {
      "NOTES_COLLECTION_SAVE_OK"
    },
  )
}
