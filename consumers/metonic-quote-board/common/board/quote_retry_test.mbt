///|
fn retry_quote_button(app : @app.Application) -> @semantics.NodeRef {
  (app.view)()
  .iter()
  .find_first(control => control.element.text == "Retry quote")
  .unwrap().element.reference.unwrap()
}

///|
fn quote_status(app : @app.Application) -> @semantics.NodeRef {
  ignore(app.synchronize_components(None))
  (app.view)()
  .iter()
  .find_first(control => {
    control.kind == @app.Status && control.element.bounds.y == 256
  })
  .unwrap().element.reference.unwrap()
}

///|
async test "a failed quote stays failed until Retry requests the same input" {
  let attempts = Ref(0)
  let app = create_with_quote_result(_ => (), _ => Ok(2), _ => Ok(()), (
    _,
    stock,
    quantity,
  ) => {
    attempts.val += 1
    if attempts.val == 1 {
      Err("quote service unavailable")
    } else {
      Ok((100 + stock) * quantity)
    }
  })
  (app.connect_tasks)(@task.task_control(_ => ()))
  let item = (app.initialize)().unwrap()
  item.invalidate()
  for request in item.members() {
    assert_eq(request.prepare().unwrap().run().apply(), @task.Changed)
  }
  let quotes : Array[@task.Request] = []
  assert_true(
    app.reconcile_tasks(request => {
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
  assert_eq(line(app, 7), "Shipping: failed for amber x1")
  let status = quote_status(app)
  let failed = @semantics.node(app.editor, status).unwrap()
  assert_eq(failed.role, @semantics.Status)
  assert_true(failed.invalid)
  assert_false(failed.name.contains("quote service unavailable"))
  assert_eq(attempts.val, 1)
  assert_false(app.reconcile_tasks(_ => abort("failure must not auto-retry")))
  assert_eq(attempts.val, 1)
  assert_true((app.activate)(retry_quote_button(app)) is None)
  assert_true(
    app.reconcile_tasks(request => {
      quotes.push(request)
      request.invalidate()
      true
    }),
  )
  assert_eq(quotes.length(), 2)
  ignore(app.publish())
  assert_eq(line(app, 7), "Shipping: loading")
  assert_eq(quote_status(app), status)
  assert_false(@semantics.node(app.editor, status).unwrap().invalid)
  assert_eq(
    quotes[1].members()[0].prepare().unwrap().run().apply(),
    @task.Changed,
  )
  ignore(app.publish())
  assert_eq(line(app, 7), "Shipping: 112 for 1")
  assert_eq(quote_status(app), status)
  assert_eq(attempts.val, 2)
  assert_false(
    (app.view)().any(control => control.element.text == "Retry quote"),
  )
  (app.dispose)()
  assert_true(@semantics.node(app.editor, status) is Err("stale_target"))
}

///|
async test "new quote input rejects a late result from the previous quantity" {
  let app = create_with_quote_result(_ => (), _ => Ok(2), _ => Ok(()), (
    _,
    stock,
    quantity,
  ) => {
    if quantity == 1 {
      Err("quote service unavailable")
    } else {
      Ok((100 + stock) * quantity)
    }
  })
  (app.connect_tasks)(@task.task_control(_ => ()))
  let item = (app.initialize)().unwrap()
  item.invalidate()
  for request in item.members() {
    assert_eq(request.prepare().unwrap().run().apply(), @task.Changed)
  }
  let quotes : Array[@task.Request] = []
  assert_true(
    app.reconcile_tasks(request => {
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
  assert_eq(line(app, 7), "Shipping: failed for amber x1")
  assert_true((app.activate)(button(app, 2)) is None)
  assert_true(
    app.reconcile_tasks(request => {
      quotes.push(request)
      request.invalidate()
      true
    }),
  )
  let late = quotes[1].members()[0].prepare().unwrap().run()
  ignore(app.publish())
  assert_eq(line(app, 7), "Shipping: loading")
  assert_true((app.activate)(button(app, 1)) is Some(_))
  assert_eq(late.apply(), @task.Rejected)
  ignore(app.publish())
  assert_eq(line(app, 4), "Item: blue · Quantity: 2 · Currency: JPY")
  assert_eq(line(app, 7), "Shipping: waiting for item")
  (app.dispose)()
}
