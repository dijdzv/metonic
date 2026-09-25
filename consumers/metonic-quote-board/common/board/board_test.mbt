///|
fn line(app : @app.Application, index : Int) -> String {
  ignore(app.synchronize_components(None))
  (app.view)().filter(control => control.kind == @app.Text)[index - 4].element.text
}

///|
fn button(app : @app.Application, index : Int) -> @semantics.NodeRef {
  (app.view)()[if index == 2 { 6 } else { index }].element.reference.unwrap()
}

///|
async test "development diagnostics explain rejected D without note contents" {
  let diagnostics = @async_state.TraceRegistry::new(32)
  let app = create(_ => (), diagnostics=Some(diagnostics))
  (app.connect_tasks)(@task.task_control(_ => ()))
  let initial = (app.initialize)().unwrap()
  initial.invalidate()
  assert_eq(diagnostics.owners().length(), 3)
  assert_eq(diagnostics.sources().length(), 4)
  for request in initial.members() {
    assert_eq(request.prepare().unwrap().run().apply(), @task.Changed)
  }
  assert_true(app.reconcile_downstreams(_ => false))
  assert_eq(diagnostics.derived().length(), 1)
  assert_eq(diagnostics.derived()[0].phase, "blocked")
  assert_eq(
    diagnostics.sources().filter(source => source.phase == "pending").length(),
    0,
  )
  assert_true(
    diagnostics.snapshot_json().stringify().contains("admission_rejected"),
  )
  let note = app.default_input.unwrap()
  ignore(
    (app.edited)({
      target: note,
      text: "private note marker",
      revision: @semantics.revision(app.editor),
    }),
  )
  assert_false(
    diagnostics.snapshot_json().stringify().contains("private note marker"),
  )
  (app.dispose)()
  assert_eq(diagnostics.owners().length(), 0)
  assert_eq(diagnostics.sources().length(), 0)
}

///|
async test "real Driver capacity denial leaves D blocked until retry" {
  let diagnostics = @async_state.TraceRegistry::new(32)
  let app = create(_ => (), diagnostics=Some(diagnostics))
  let driver = @driver.driver()
  assert_true(
    driver.observe((operation, event) => {
      diagnostics.driver_event(operation, event)
    }),
  )
  (app.connect_tasks)(
    @task.task_control(operation => ignore(driver.cancel_operation(operation))),
  )
  let initial = (app.initialize)().unwrap()
  initial.invalidate()
  for request in initial.members() {
    assert_eq(request.prepare().unwrap().run().apply(), @task.Changed)
  }
  for _ in 0..<16 {
    assert_true(
      driver.submit(@task.cancel(() => (), operation=@task.Operation::new())),
    )
  }
  assert_true(app.reconcile_downstreams(request => driver.submit(request)))
  let denial = diagnostics.events().last().unwrap()
  assert_eq(denial.kind, @async_state.AdmissionRejected)
  assert_eq(denial.denial, Some(@task.PendingCapacity))
  assert_eq(diagnostics.derived()[0].phase, "blocked")
  assert_eq(
    diagnostics.sources().filter(source => source.phase == "pending").length(),
    0,
  )
  assert_false(
    app.reconcile_downstreams(_ => abort("D repeated rejected admission")),
  )
  driver.close()
  let retry = (app.view)()
  .iter()
  .find_first(control => control.element.text == "Retry quote")
  .unwrap().element.reference.unwrap()
  assert_true((app.activate)(retry) is None)
  let requests : Array[@task.Request] = []
  assert_true(
    app.reconcile_downstreams(request => {
      requests.push(request)
      request.invalidate()
      true
    }),
  )
  assert_eq(requests.length(), 1)
  assert_eq(
    diagnostics.sources().filter(source => source.phase == "pending").length(),
    1,
  )
  assert_eq(
    requests[0].members()[0].prepare().unwrap().run().apply(),
    @task.Changed,
  )
  ignore(app.publish())
  assert_eq(line(app, 7), "Shipping: 112 for 1")
  (app.dispose)()
}

///|
async test "currency completes before the item without admitting D early" {
  let app = create(_ => ())
  (app.connect_tasks)(@task.task_control(_ => ()))
  let item = (app.initialize)().unwrap()
  item.invalidate()
  let rate = (app.activate)(button(app, 5)).unwrap()
  rate.invalidate()
  assert_eq(rate.members().length(), 1)
  assert_eq(rate.members()[0].prepare().unwrap().run().apply(), @task.Changed)
  ignore(app.publish())
  assert_eq(line(app, 7), "Shipping: waiting for item")
  assert_false(app.reconcile_downstreams(_ => abort("D must wait for A/B")))
  for request in item.members() {
    assert_eq(request.prepare().unwrap().run().apply(), @task.Changed)
  }
  let quotes : Array[@task.Request] = []
  assert_true(
    app.reconcile_downstreams(request => {
      quotes.push(request)
      request.invalidate()
      true
    }),
  )
  assert_eq(quotes.length(), 1)
  assert_eq(
    quotes[0].members()[0].prepare().unwrap().run().apply(),
    @task.Changed,
  )
  ignore(app.publish())
  assert_eq(line(app, 7), "Shipping: 224 USD for 1")
  assert_false(app.reconcile_downstreams(_ => abort("C must not restart D")))
  (app.dispose)()
}

///|
async test "currency changes retain only same-demand aggregates and leave D intact" {
  let app = create(_ => ())
  (app.connect_tasks)(@task.task_control(_ => ()))
  let item = (app.initialize)().unwrap()
  item.invalidate()
  for request in item.members() {
    assert_eq(request.prepare().unwrap().run().apply(), @task.Changed)
  }
  let quotes : Array[@task.Request] = []
  assert_true(
    app.reconcile_downstreams(request => {
      quotes.push(request)
      request.invalidate()
      true
    }),
  )
  assert_eq(
    quotes[0].members()[0].prepare().unwrap().run().apply(),
    @task.Changed,
  )
  ignore(app.publish())
  assert_eq(line(app, 7), "Shipping: 112 for 1")

  let rate = (app.activate)(button(app, 5)).unwrap()
  rate.invalidate()
  ignore(app.publish())
  assert_eq(line(app, 7), "Shipping: loading")
  assert_false(
    app.reconcile_downstreams(_ => abort("currency must not restart D")),
  )
  assert_eq(rate.members()[0].prepare().unwrap().run().apply(), @task.Changed)
  ignore(app.publish())
  assert_eq(line(app, 7), "Shipping: 224 USD for 1")

  let refresh = (app.activate)(button(app, 5)).unwrap()
  refresh.invalidate()
  ignore(app.publish())
  assert_eq(line(app, 7), "Shipping: loading (previous 224 USD)")
  let stale = refresh.members()[0].prepare().unwrap().run()
  assert_true((app.activate)(button(app, 4)) is None)
  assert_eq(stale.apply(), @task.Rejected)
  ignore(app.publish())
  assert_eq(line(app, 7), "Shipping: 112 for 1")
  assert_false(app.reconcile_downstreams(_ => abort("yen must not restart D")))
  assert_eq(quotes.length(), 1)
  (app.dispose)()
}

///|
async test "a failed currency source never becomes a converted quote" {
  let app = create_with_rate(_ => (), _ => Err("rate unavailable"))
  (app.connect_tasks)(@task.task_control(_ => ()))
  let item = (app.initialize)().unwrap()
  item.invalidate()
  for request in item.members() {
    assert_eq(request.prepare().unwrap().run().apply(), @task.Changed)
  }
  let quotes : Array[@task.Request] = []
  assert_true(
    app.reconcile_downstreams(request => {
      quotes.push(request)
      request.invalidate()
      true
    }),
  )
  assert_eq(
    quotes[0].members()[0].prepare().unwrap().run().apply(),
    @task.Changed,
  )
  ignore(app.publish())
  assert_eq(line(app, 7), "Shipping: 112 for 1")
  let rate = (app.activate)(button(app, 5)).unwrap()
  rate.invalidate()
  assert_eq(rate.members()[0].prepare().unwrap().run().apply(), @task.Changed)
  ignore(app.publish())
  assert_eq(line(app, 7), "Shipping: failed")
  assert_false(
    app.reconcile_downstreams(_ => abort("C failure must not restart D")),
  )
  assert_true((app.activate)(button(app, 4)) is None)
  ignore(app.publish())
  assert_eq(line(app, 7), "Shipping: 112 for 1")
  (app.dispose)()
}

///|
async test "quantity restarts D while reusing a completed independent currency" {
  let app = create(_ => ())
  (app.connect_tasks)(@task.task_control(_ => ()))
  let item = (app.initialize)().unwrap()
  item.invalidate()
  let rate = (app.activate)(button(app, 5)).unwrap()
  rate.invalidate()
  for request in item.members() {
    assert_eq(request.prepare().unwrap().run().apply(), @task.Changed)
  }
  assert_eq(rate.members()[0].prepare().unwrap().run().apply(), @task.Changed)
  let quotes : Array[@task.Request] = []
  assert_true(
    app.reconcile_downstreams(request => {
      quotes.push(request)
      request.invalidate()
      true
    }),
  )
  assert_eq(
    quotes[0].members()[0].prepare().unwrap().run().apply(),
    @task.Changed,
  )
  ignore(app.publish())
  assert_eq(line(app, 7), "Shipping: 224 USD for 1")
  assert_true((app.activate)(button(app, 2)) is None)
  assert_true(
    app.reconcile_downstreams(request => {
      quotes.push(request)
      request.invalidate()
      true
    }),
  )
  assert_eq(quotes.length(), 2)
  ignore(app.publish())
  assert_eq(line(app, 7), "Shipping: loading")
  assert_eq(
    quotes[1].members()[0].prepare().unwrap().run().apply(),
    @task.Changed,
  )
  ignore(app.publish())
  assert_eq(line(app, 7), "Shipping: 448 USD for 2")
  (app.dispose)()
}

///|
async test "recreating detail revokes old controls and rejects old shipping results" {
  let app = create(_ => ())
  (app.connect_tasks)(@task.task_control(_ => ()))
  let first = (app.initialize)().unwrap()
  first.invalidate()
  for request in first.members() {
    assert_eq(request.prepare().unwrap().run().apply(), @task.Changed)
  }
  let quotes : Array[@task.Request] = []
  assert_true(
    app.reconcile_downstreams(request => {
      quotes.push(request)
      request.invalidate()
      true
    }),
  )
  let old_result = quotes[0].members()[0].prepare().unwrap().run()
  let old_quantity = button(app, 2)
  assert_true((app.activate)(button(app, 3)) is None)
  ignore(app.publish())
  assert_eq(line(app, 7), "Shipping: detail hidden")
  assert_true(@semantics.node(app.editor, old_quantity) is Err(_))
  assert_true((app.activate)(old_quantity) is None)
  assert_eq(old_result.apply(), @task.Rejected)

  assert_true((app.activate)(button(app, 3)) is None)
  let new_quantity = button(app, 2)
  assert_true(old_quantity != new_quantity)
  assert_true((app.activate)(old_quantity) is None)
  assert_eq(line(app, 4), "Item: amber · Quantity: 1 · Currency: JPY")
  assert_true(
    app.reconcile_downstreams(request => {
      quotes.push(request)
      request.invalidate()
      true
    }),
  )
  assert_eq(quotes.length(), 2)
  ignore(app.publish())
  assert_eq(line(app, 7), "Shipping: loading")
  assert_eq(
    quotes[1].members()[0].prepare().unwrap().run().apply(),
    @task.Changed,
  )
  ignore(app.publish())
  assert_eq(line(app, 7), "Shipping: 112 for 1")
  (app.dispose)()
}

///|
async test "stock-first and detail-first item requests start shipping only after a coherent pair" {
  let app = create(_ => ())
  (app.connect_tasks)(@task.task_control(_ => ()))
  let first = (app.initialize)().unwrap()
  first.invalidate()
  ignore(app.publish())
  assert_eq(line(app, 5), "Detail: loading")
  assert_eq(line(app, 6), "Stock: loading")
  assert_eq(line(app, 7), "Shipping: waiting for item")

  let amber = first.members()
  assert_eq(amber[1].prepare().unwrap().run().apply(), @task.Changed)
  assert_false(app.reconcile_downstreams(_ => abort("D must wait for detail")))
  ignore(app.publish())
  assert_eq(line(app, 5), "Detail: loading")
  assert_eq(line(app, 6), "Stock: 12")
  assert_eq(amber[0].prepare().unwrap().run().apply(), @task.Changed)
  let admitted : Array[@task.Request] = []
  assert_true(
    app.reconcile_downstreams(request => {
      admitted.push(request)
      request.invalidate()
      true
    }),
  )
  assert_eq(admitted.length(), 1)
  ignore(app.publish())
  assert_eq(line(app, 7), "Shipping: loading")
  assert_eq(
    admitted[0].members()[0].prepare().unwrap().run().apply(),
    @task.Changed,
  )
  ignore(app.publish())
  assert_eq(line(app, 7), "Shipping: 112 for 1")

  let second = (app.activate)(button(app, 1)).unwrap()
  second.invalidate()
  ignore(app.reconcile_downstreams(_ => true))
  ignore(app.publish())
  assert_eq(line(app, 4), "Item: blue · Quantity: 1 · Currency: JPY")
  assert_eq(line(app, 7), "Shipping: waiting for item")
  let blue = second.members()
  assert_eq(blue[0].prepare().unwrap().run().apply(), @task.Changed)
  assert_false(app.reconcile_downstreams(_ => abort("D must wait for stock")))
  ignore(app.publish())
  assert_eq(line(app, 5), "Detail: Blue stool")
  assert_eq(line(app, 6), "Stock: loading")
  assert_eq(blue[1].prepare().unwrap().run().apply(), @task.Changed)
  assert_true(
    app.reconcile_downstreams(request => {
      admitted.push(request)
      request.invalidate()
      true
    }),
  )
  assert_eq(admitted.length(), 2)
  assert_eq(
    admitted[1].members()[0].prepare().unwrap().run().apply(),
    @task.Changed,
  )
  ignore(app.publish())
  assert_eq(line(app, 7), "Shipping: 107 for 1")
  (app.dispose)()
}

///|
async test "quantity change rejects an obsolete quote even when its result arrives later" {
  let app = create(_ => ())
  (app.connect_tasks)(@task.task_control(_ => ()))
  let first = (app.initialize)().unwrap()
  first.invalidate()
  for request in first.members() {
    assert_eq(request.prepare().unwrap().run().apply(), @task.Changed)
  }
  let quotes : Array[@task.Request] = []
  assert_true(
    app.reconcile_downstreams(request => {
      quotes.push(request)
      request.invalidate()
      true
    }),
  )
  let old = quotes[0].members()[0].prepare().unwrap().run()
  assert_true((app.activate)(button(app, 2)) is None)
  assert_true(
    app.reconcile_downstreams(request => {
      quotes.push(request)
      request.invalidate()
      true
    }),
  )
  assert_eq(old.apply(), @task.Rejected)
  ignore(app.publish())
  assert_eq(line(app, 7), "Shipping: loading")
  assert_eq(
    quotes[1].members()[0].prepare().unwrap().run().apply(),
    @task.Changed,
  )
  ignore(app.publish())
  assert_eq(line(app, 7), "Shipping: 224 for 2")
  (app.dispose)()
}

///|
async test "switching items rejects an unfinished detail from the previous selection" {
  let app = create(_ => ())
  (app.connect_tasks)(@task.task_control(_ => ()))
  let amber = (app.initialize)().unwrap()
  amber.invalidate()
  let first_amber_quantity = button(app, 2)
  let late_detail = amber.members()[0].prepare().unwrap().run()
  let blue = (app.activate)(button(app, 1)).unwrap()
  blue.invalidate()
  let blue_quantity = button(app, 2)
  assert_true(blue_quantity != first_amber_quantity)
  assert_true(@semantics.node(app.editor, first_amber_quantity) is Err(_))
  assert_eq(late_detail.apply(), @task.Rejected)
  for request in blue.members() {
    assert_eq(request.prepare().unwrap().run().apply(), @task.Changed)
  }
  let quote : Array[@task.Request] = []
  assert_true(
    app.reconcile_downstreams(request => {
      quote.push(request)
      request.invalidate()
      true
    }),
  )
  assert_eq(quote.length(), 1)
  assert_eq(
    quote[0].members()[0].prepare().unwrap().run().apply(),
    @task.Changed,
  )
  ignore(app.publish())
  assert_eq(line(app, 4), "Item: blue · Quantity: 1 · Currency: JPY")
  assert_eq(line(app, 5), "Detail: Blue stool")
  assert_eq(line(app, 7), "Shipping: 107 for 1")
  let recreated_amber = (app.activate)(button(app, 0)).unwrap()
  recreated_amber.invalidate()
  let next_amber_quantity = button(app, 2)
  assert_true(next_amber_quantity != first_amber_quantity)
  assert_true(@semantics.node(app.editor, blue_quantity) is Err(_))
  for request in recreated_amber.members() {
    assert_eq(request.prepare().unwrap().run().apply(), @task.Changed)
  }
  let fresh_quotes : Array[@task.Request] = []
  assert_true(
    app.reconcile_downstreams(request => {
      fresh_quotes.push(request)
      request.invalidate()
      true
    }),
  )
  assert_eq(fresh_quotes.length(), 1)
  assert_eq(
    fresh_quotes[0].members()[0].prepare().unwrap().run().apply(),
    @task.Changed,
  )
  ignore(app.publish())
  assert_eq(line(app, 7), "Shipping: 112 for 1")
  (app.dispose)()
}
