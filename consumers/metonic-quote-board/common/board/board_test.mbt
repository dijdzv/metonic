///|
fn line(app : @app.Application, index : Int) -> String {
  (app.view)()[index + 1].element.text
}

///|
fn button(app : @app.Application, index : Int) -> @semantics.NodeRef {
  (app.view)()[if index == 2 { 4 } else { index }].element.reference.unwrap()
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
  assert_eq((app.view)()[7].element.text, "Shipping: detail hidden")
  assert_true(@semantics.node(app.editor, old_quantity) is Err(_))
  assert_eq(old_result.apply(), @task.Rejected)

  assert_true((app.activate)(button(app, 3)) is None)
  let new_quantity = button(app, 2)
  assert_true(old_quantity != new_quantity)
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
  assert_eq(line(app, 4), "Item: blue · Quantity: 1")
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
  assert_eq(line(app, 4), "Item: blue · Quantity: 1")
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
