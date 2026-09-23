///|
async test "close confirmation preserves edits through cancel and failed save retry" {
  let stored = Ref(Some("original"))
  let fail_save = Ref(true)
  let writes = Ref(0)
  let app = create_collection(
    {
      load: () => Ok(stored.val),
      save: value => {
        writes.val += 1
        if fail_save.val {
          Err("disk unavailable")
        } else {
          stored.val = Some(value)
          Ok(())
        }
      },
    },
    () => (),
    _ => (),
  )
  finish((app.initialize)())
  let activate = index => {
    (app.activate)((app.view)()[index].element.reference.unwrap())
  }
  assert_eq(
    @semantics.set_text(
      app.editor,
      app.default_input.unwrap(),
      "draft 日本語",
    ),
    "",
  )
  assert_false((app.can_close)())
  assert_false((app.close_ready)())
  assert_eq((app.view)()[1].element.text, "Save all")
  (app.close_requested)()
  (app.close_requested)()
  assert_eq(writes.val, 0)
  assert_eq((app.view)()[1].element.text, "Save")
  assert_eq((app.view)()[2].element.text, "Discard")
  assert_eq((app.view)()[3].element.text, "Cancel")
  assert_false(
    @semantics.node(app.editor, app.default_input.unwrap()).unwrap().enabled,
  )
  ignore(activate(3))
  assert_false((app.close_ready)())
  assert_true(
    @semantics.node(app.editor, app.default_input.unwrap()).unwrap().enabled,
  )
  assert_eq(
    @semantics.node(app.editor, app.default_input.unwrap()).unwrap().value,
    "draft 日本語",
  )
  (app.close_requested)()
  finish(activate(1))
  assert_false((app.close_ready)())
  assert_false((app.can_close)())
  assert_true(
    (app.view)().last().unwrap().element.text.contains("disk unavailable"),
  )
  assert_eq(stored.val, Some("original"))
  fail_save.val = false
  finish(activate(1))
  assert_eq(writes.val, 2)
  assert_true((app.close_ready)())
  assert_true((app.can_close)())
  assert_eq(
    @collection.decode(stored.val).unwrap().items()[0].text,
    "draft 日本語",
  )
  (app.stop)()
}

///|
async test "close discard does not require an invalid draft to pass save validation" {
  let app = create_collection(
    {
      load: () => Ok(Some("original")),
      save: _ => fail("discard must not save"),
    },
    () => (),
    _ => (),
  )
  finish((app.initialize)())
  assert_eq(
    @semantics.set_text(
      app.editor,
      app.default_input.unwrap(),
      Array::make(1025, "x").join(""),
    ),
    "",
  )
  (app.close_requested)()
  ignore((app.activate)((app.view)()[2].element.reference.unwrap()))
  assert_true((app.can_close)())
  assert_true((app.close_ready)())
  assert_eq(
    @semantics.node(app.editor, app.default_input.unwrap()).unwrap().value,
    "original",
  )
  (app.stop)()
}

///|
async test "cancel close during an existing save prevents later automatic exit" {
  let writes = Ref(0)
  let app = create_collection(
    {
      load: () => Ok(Some("original")),
      save: _ => {
        writes.val += 1
        Ok(())
      },
    },
    () => (),
    _ => (),
  )
  finish((app.initialize)())
  assert_eq(
    @semantics.set_text(app.editor, app.default_input.unwrap(), "changed"),
    "",
  )
  let request = (app.activate)((app.view)()[1].element.reference.unwrap()).unwrap()
  request.invalidate()
  let completion = request.prepare().unwrap().run()
  (app.close_requested)()
  (app.close_requested)()
  assert_false((app.can_close)())
  assert_false((app.close_ready)())
  ignore((app.activate)((app.view)()[3].element.reference.unwrap()))
  assert_eq(completion.apply(), @task.Changed)
  assert_eq(writes.val, 1)
  assert_true((app.can_close)())
  assert_false((app.close_ready)())
  (app.stop)()
}
