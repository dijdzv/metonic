///|
async fn finish(request : @task.Request?) -> Unit {
  let request = request.unwrap()
  request.invalidate()
  let completed = request.prepare().unwrap().run()
  assert_eq(completed.apply(), @task.Changed)
}

///|
async test "saving a collection snapshot does not erase edits made before completion" {
  let stored : Ref[String?] = Ref(None)
  let app = create_collection(
    {
      load: () => Ok(stored.val),
      save: value => {
        stored.val = Some(value)
        Ok(())
      },
    },
    () => (),
    _ => (),
  )
  finish((app.initialize)())
  let activate = index => {
    (app.activate)((app.view)()[index].element.reference.unwrap())
  }
  assert_false(
    @semantics.node(app.editor, app.default_input.unwrap()).unwrap().enabled,
  )
  ignore(activate(3))
  assert_eq(
    @semantics.set_text(app.editor, app.default_input.unwrap(), "first"),
    "",
  )
  ignore(activate(3))
  assert_eq(
    @semantics.set_text(app.editor, app.default_input.unwrap(), "second"),
    "",
  )
  let request = activate(1).unwrap()
  request.invalidate()
  let completion = request.prepare().unwrap().run()
  assert_eq(
    @semantics.set_text(app.editor, app.default_input.unwrap(), "newer"),
    "",
  )
  assert_false((app.can_close)())
  assert_eq(completion.apply(), @task.Changed)
  assert_false((app.can_close)())
  assert_eq(@collection.decode(stored.val).unwrap().items()[1].text, "second")
  ignore(activate(7))
  assert_eq(
    @semantics.node(app.editor, app.default_input.unwrap()).unwrap().value,
    "first",
  )
  ignore(activate(8))
  assert_eq(
    @semantics.node(app.editor, app.default_input.unwrap()).unwrap().value,
    "newer",
  )
  finish(activate(1))
  assert_true((app.can_close)())
  assert_eq(@collection.decode(stored.val).unwrap().items()[1].text, "newer")
  (app.stop)()
}

///|
async test "invalid stored collections cannot be overwritten through disabled controls" {
  let stored = Ref(Some("METONIC_NOTES\ninvalid"))
  let writes = Ref(0)
  let app = create_collection(
    {
      load: () => Ok(stored.val),
      save: _ => {
        writes.val += 1
        Ok(())
      },
    },
    () => (),
    _ => (),
  )
  finish((app.initialize)())
  assert_true(
    (app.view)().last().unwrap().element.text.has_prefix("Load failed:"),
  )
  for index in [2, 3, 4, 5, 6] {
    assert_true(
      (app.activate)((app.view)()[index].element.reference.unwrap()) is None,
    )
  }
  assert_eq(writes.val, 0)
  assert_false(
    @semantics.node(app.editor, app.default_input.unwrap()).unwrap().enabled,
  )
  stored.val = Some("legacy 日本語")
  finish((app.activate)((app.view)()[1].element.reference.unwrap()))
  assert_eq(
    @semantics.node(app.editor, app.default_input.unwrap()).unwrap().value,
    "legacy 日本語",
  )
  assert_true((app.can_close)())
  assert_eq(writes.val, 0)
  (app.stop)()
}

///|
async test "input errors do not erase save failures or unsaved text" {
  let app = create_collection(
    { load: () => Ok(Some("original")), save: _ => Err("disk unavailable"), },
    () => (),
    _ => (),
  )
  finish((app.initialize)())
  assert_eq(
    @semantics.set_text(
      app.editor,
      app.default_input.unwrap(),
      "edited 日本語",
    ),
    "",
  )
  finish((app.activate)((app.view)()[1].element.reference.unwrap()))
  let failure = (app.view)().last().unwrap().element.text
  assert_true(failure.has_prefix("Save failed:"))
  (app.input_error)(Some("Clipboard: busy"))
  assert_eq(
    (app.view)().last().unwrap().element.text,
    failure + " | Clipboard: busy",
  )
  (app.input_error)(None)
  assert_eq((app.view)().last().unwrap().element.text, failure)
  assert_eq(
    @semantics.node(app.editor, app.default_input.unwrap()).unwrap().value,
    "edited 日本語",
  )
  assert_false((app.can_close)())
  (app.stop)()
}
