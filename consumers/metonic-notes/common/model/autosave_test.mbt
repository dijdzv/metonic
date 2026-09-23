///|
fn edited(app : @application.Application, text : String) -> @task.Request raise {
  let target = app.default_input.unwrap()
  assert_eq(@semantics.set_text(app.editor, target, text), "")
  (app.edited)({ target, text, revision: @semantics.revision(app.editor), }).unwrap()
}

///|
async test "committed edits wait then autosave and manual retry bypasses debounce" {
  let stored = Ref(Some("original"))
  let delays : Array[Int] = []
  let fail_save = Ref(false)
  let app = create_collection(
    {
      load: () => Ok(stored.val),
      save: value => {
        if fail_save.val {
          Err("full")
        } else {
          stored.val = Some(value)
          Ok(())
        }
      },
    },
    () => (),
    delay => delays.push(delay),
  )
  initialize(app)
  let request = edited(app, "autosaved")
  assert_eq(stored.val, Some("original"))
  finish(Some(request))
  assert_eq(delays, [500])
  assert_eq(
    @collection.decode(stored.val).unwrap().items()[0].text,
    "autosaved",
  )
  assert_true((app.can_close)())
  fail_save.val = true
  finish(Some(edited(app, "keep me")))
  assert_false((app.can_close)())
  assert_true((app.view)().last().unwrap().element.text.contains("full"))
  fail_save.val = false
  finish((app.activate)((app.view)()[1].element.reference.unwrap()))
  assert_eq(delays, [500, 500])
  assert_eq(@collection.decode(stored.val).unwrap().items()[0].text, "keep me")
  (app.stop)()
}

///|
async test "replacement reconciles a written snapshot before its completion was applied" {
  let stored = Ref(Some("original"))
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
  initialize(app)
  let first = edited(app, "first")
  first.invalidate()
  let stale = first.prepare().unwrap().run()
  let second = edited(app, "second")
  second.invalidate()
  let next = second.prepare().unwrap()
  assert_eq(stale.apply(), @task.Rejected)
  assert_false((app.can_close)())
  assert_eq(next.run().apply(), @task.Changed)
  assert_eq(@collection.decode(stored.val).unwrap().items()[0].text, "second")
  assert_true((app.can_close)())
  (app.stop)()
}

///|
async test "close requested during debounce preserves the unsaved close decision" {
  let entered = @cond_var.Cond()
  let release = @cond_var.Cond()
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
    _ => {
      entered.signal()
      release.wait()
    },
  )
  initialize(app)
  let request = edited(app, "draft")
  request.invalidate()
  let work = request.prepare().unwrap()
  @async.with_task_group(group => {
    let running = group.spawn(() => work.run())
    entered.wait()
    (app.close_requested)()
    release.signal()
    assert_eq(running.wait().apply(), @task.Unchanged)
  })
  assert_eq(writes.val, 0)
  assert_false((app.can_close)())
  assert_false((app.close_ready)())
  assert_eq((app.view)()[1].element.text, "Save")
  (app.stop)()
}

///|
async test "discard cancels debounce before it can write the discarded draft" {
  let entered = @cond_var.Cond()
  let blocked = @cond_var.Cond()
  let acknowledged = @cond_var.Cond()
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
    _ => {
      entered.signal()
      blocked.wait()
    },
  )
  initialize(app)
  let driver = @driver.driver()
  assert_true(driver.submit(edited(app, "discard me")))
  @async.with_task_group(group => {
    let running = group.spawn(() => {
      driver.run(completion => ignore(completion.apply()))
    })
    entered.wait()
    let discard = (app.activate)((app.view)()[2].element.reference.unwrap()).unwrap()
    assert_true(driver.submit(discard, on_prepared=() => acknowledged.signal()))
    acknowledged.wait()
    assert_eq(
      @semantics.node(app.editor, app.default_input.unwrap()).unwrap().value,
      "original",
    )
    assert_true((app.can_close)())
    driver.close()
    running.wait()
  })
  assert_eq(writes.val, 0)
  (app.stop)()
}

///|
async test "queued autosave cannot silently retry a newly completed storage failure" {
  let writes = Ref(0)
  let app = create_collection(
    {
      load: () => Ok(Some("original")),
      save: _ => {
        writes.val += 1
        Err("disk full")
      },
    },
    () => (),
    _ => (),
  )
  initialize(app)
  let first = edited(app, "first")
  first.invalidate()
  let stale = first.prepare().unwrap().run()
  let second = edited(app, "latest")
  second.invalidate()
  assert_true(second.prepare() is None)
  assert_eq(stale.apply(), @task.Rejected)
  assert_eq(writes.val, 1)
  assert_false((app.can_close)())
  assert_true((app.view)().last().unwrap().element.text.contains("disk full"))
  (app.stop)()
}
