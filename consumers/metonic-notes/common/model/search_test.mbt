///|
fn search_input(app : @application.Application) -> @semantics.NodeRef {
  (app.view)()
  .iter()
  .find_first(control => {
    control.element.reference is Some(reference) &&
    @semantics.node(app.editor, reference).unwrap().name == "Search memos"
  })
  .unwrap().element.reference.unwrap()
}

///|
fn search_edit(
  app : @application.Application,
  text : String,
) -> @task.Request raise {
  let target = search_input(app)
  assert_eq(@semantics.set_text(app.editor, target, text), "")
  (app.edited)({ target, text, revision: @semantics.revision(app.editor), }).unwrap()
}

///|
fn listed_memos(app : @application.Application) -> Array[String] {
  (app.view)()
  .filter(control => {
    control.kind == @application.Button &&
    control.element.text.contains("Memo ")
  })
  .map(control => control.element.text)
}

///|
async test "search finishes while autosave remains pending and never cancels its write" {
  let (document, alpha) = @collection.empty().create_note().unwrap()
  let document = document.edit(alpha, "Alpha").unwrap()
  let (document, beta) = document.create_note().unwrap()
  let document = document.edit(beta, "Beta").unwrap()
  let stored = Ref(Some(document.encode()))
  let save_started = @cond_var.Cond()
  let release_save = @cond_var.Cond()
  let search_finished = @cond_var.Cond()
  let save_finished = @cond_var.Cond()
  let app = create_collection(
    {
      load: () => Ok(stored.val),
      save: value => {
        stored.val = Some(value)
        Ok(())
      },
    },
    () => (),
    delay => {
      if delay == 500 {
        save_started.signal()
        release_save.wait()
      }
    },
  )
  finish((app.initialize)())
  let driver = @driver.driver()
  assert_true(driver.submit(edited(app, "Alpha latest")))
  @async.with_task_group(group => {
    let running = group.spawn(() => {
      driver.run(completion => {
        ignore(completion.apply())
        if listed_memos(app) == ["Memo 2"] {
          search_finished.signal()
        }
        if (app.can_close)() {
          save_finished.signal()
        }
      })
    })
    save_started.wait()
    assert_true(driver.submit(search_edit(app, "Beta")))
    search_finished.wait()
    assert_eq(listed_memos(app), ["Memo 2"])
    assert_eq(@collection.decode(stored.val).unwrap().items()[0].text, "Alpha")
    assert_false((app.can_close)())
    release_save.signal()
    save_finished.wait()
    assert_eq(
      @collection.decode(stored.val).unwrap().items()[0].text,
      "Alpha latest",
    )
    assert_true(driver.submit(search_edit(app, "")))
    assert_eq(listed_memos(app).length(), 2)
    driver.close()
    running.wait()
  })
  (app.stop)()
}
