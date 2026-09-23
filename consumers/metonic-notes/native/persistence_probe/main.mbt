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
        let edit = value => {
          assert_eq(@semantics.focus(app.editor, app.default_input.unwrap()), "")
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
            "日本語メモ1\n保存と復元",
          )
          activate(6)
          activate(7)
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
          assert_eq(
            (handle.inspect)().text,
            "日本語メモ1\n保存と復元",
          )
          assert_false((app.can_close)())
          activate(2)
          activate(6)
          activate(7)
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
          assert_eq(status(), "Unsaved changes")
          assert_false((app.can_close)())
          (handle.apply)(@window_host.Close)
          assert_eq((app.view)()[3].element.text, "Cancel")
          activate(3)
          assert_eq(
            (handle.inspect)().text,
            "日本語メモ1\n保存と復元",
          )
          @fs.mkdir(directory + "/snapshot.pending")
          activate(1)
          while status() == "Saving..." {
            @async.sleep(1)
          }
          assert_true(status().has_prefix("Save failed:"))
          assert_false((app.can_close)())
          assert_false(@fs.exists(directory + "/snapshot"))
          @fs.rmdir(directory + "/snapshot.pending")
          activate(1)
          while status() == "Saving..." {
            @async.sleep(1)
          }
          assert_eq(status(), "Saved")
          edit("discard this edit")
          activate(2)
          assert_eq(
            (handle.inspect)().text,
            "日本語メモ1\n保存と復元",
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
