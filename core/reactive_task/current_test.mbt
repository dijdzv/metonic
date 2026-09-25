///|
async test "related item sources and an independent rate compose in either arrival order" {
  let graph = @reactive.Graph::new()
  let root = @reactive.Scope::root(graph)
  let detail : Source[String, Int] = Source::new(root)
  let stock : Source[String, Int] = Source::new(root)
  let rate : Source[String, Int] = Source::new(root)
  let control = @task.task_control(_ => ())
  assert_true(detail.connect(control))
  assert_true(stock.connect(control))
  assert_true(rate.connect(control))
  let item_cycle = Cycle::new()
  let rate_cycle = Cycle::new()
  let group = Related::new("item-1", item_cycle)
  let total = @reactive.Memo::new(root, () => {
    let item = join_related(group.read(detail), group.read(stock), fn(a, b) {
      a + b
    })
    join_independent(item.current(), rate.current("USD", rate_cycle), fn(
      sum,
      c,
    ) {
      sum * c
    })
  })
  assert_true(total.get().view() is CurrentIdle(_))
  let a = detail.replace("item-1", item_cycle, false, () => 7).unwrap()
  let b = stock.replace("item-1", item_cycle, false, () => 3).unwrap()
  let c = rate.replace("USD", rate_cycle, false, () => 2).unwrap()
  graph.batch(() => {
    a.invalidate()
    b.invalidate()
    c.invalidate()
  })
  assert_true(total.get().view() is CurrentPending(_))
  assert_eq(b.prepare().unwrap().run().apply(), @task.Changed)
  assert_true(total.get().view() is CurrentPending(_))
  assert_eq(c.prepare().unwrap().run().apply(), @task.Changed)
  assert_true(total.get().view() is CurrentPending(_))
  assert_eq(a.prepare().unwrap().run().apply(), @task.Changed)
  match total.get().view() {
    CurrentReady(result, origins) => {
      assert_eq(result, 20)
      assert_eq(origins.length(), 3)
      let mut item_origins = 0
      let mut rate_origins = 0
      for i in 0..<origins.length() {
        match origins.origin(i) {
          Some(origin) if origin.cycle() == item_cycle => item_origins += 1
          Some(origin) if origin.cycle() == rate_cycle => rate_origins += 1
          _ => ()
        }
      }
      assert_eq(item_origins, 2)
      assert_eq(rate_origins, 1)
    }
    _ => fail("all three admitted sources should be current")
  }
  let next_cycle = Cycle::new()
  let next_group = Related::new("item-1", next_cycle)
  let next_a = detail.replace("item-1", next_cycle, false, () => 8).unwrap()
  let next_b = stock.replace("item-1", next_cycle, false, () => 4).unwrap()
  graph.batch(() => {
    next_a.invalidate()
    next_b.invalidate()
  })
  assert_eq(next_a.prepare().unwrap().run().apply(), @task.Changed)
  assert_true(
    join_related(next_group.read(detail), next_group.read(stock), fn(a, b) {
      a + b
    })
    .current()
    .view()
    is CurrentPending(_),
  )
  assert_eq(next_b.prepare().unwrap().run().apply(), @task.Changed)
  assert_true(
    join_independent(
      join_related(next_group.read(detail), next_group.read(stock), fn(a, b) {
        a + b
      }).current(),
      rate.current("USD", rate_cycle),
      fn(item, c) { item * c },
    ).view()
    is CurrentReady(24, _),
  )
  root.dispose()
}

///|
async test "proposal and admission change provenance at different boundaries" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let source : Source[String, Int] = Source::new(root)
  assert_true(source.connect(@task.task_control(_ => ())))
  let cycle = Cycle::new()
  let first = source.replace("one", cycle, false, () => 9).unwrap()
  first.invalidate()
  let pending = source.current("one", cycle)
  let pending_origin = match pending.view() {
    CurrentPending(causes) =>
      match causes.cause(0) {
        Some(PendingSource(origin)) => origin
        _ => abort("pending source has no origin")
      }
    _ => abort("admitted source should be pending")
  }
  assert_eq(first.prepare().unwrap().run().apply(), @task.Changed)
  let old = source.current("one", cycle)
  let ready_origin = match old.view() {
    CurrentReady(_, origins) => origins.origin(0).unwrap()
    _ => abort("completed source should be ready")
  }
  assert_eq(pending_origin.admission_id(), ready_origin.admission_id())
  assert_true(pending_origin.revision() != ready_origin.revision())
  assert_true(
    join_independent(pending, old, fn(a, b) { a + b }).view()
    is CurrentBlocked(_),
  )
  let second = source.replace("one", cycle, false, () => 9).unwrap()
  assert_eq(source.current("one", cycle), old)
  second.invalidate()
  assert_true(source.current("one", cycle).view() is CurrentPending(_))
  assert_eq(second.prepare().unwrap().run().apply(), @task.Changed)
  let new = source.current("one", cycle)
  assert_true(old != new)
  let forward = join_independent(old, new, fn(a, b) { a + b }).view()
  let reverse = join_independent(new, old, fn(a, b) { a + b }).view()
  assert_eq(forward, reverse)
  match forward {
    CurrentBlocked(causes) => {
      assert_eq(causes.length(), 1)
      assert_true(causes.cause(0) is Some(OriginConflict(_, _, _)))
    }
    _ => fail("equal payloads from two admissions cannot form current data")
  }
  let recreated : Source[String, Int] = Source::new(root)
  assert_true(recreated.connect(@task.task_control(_ => ())))
  let replacement = recreated.replace("one", cycle, false, () => 9).unwrap()
  replacement.invalidate()
  assert_eq(replacement.prepare().unwrap().run().apply(), @task.Changed)
  match
    join_independent(new, recreated.current("one", cycle), fn(a, b) { a + b }).view() {
    CurrentReady(18, origins) => {
      assert_eq(origins.length(), 2)
      assert_true(
        origins.origin(0).unwrap().source_id() !=
        origins.origin(1).unwrap().source_id(),
      )
    }
    _ => fail("recreated sources must have distinct identities")
  }
  root.dispose()
}

///|
async test "related group projects one typed key and cycle to each source" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let detail : Source[String, Int] = Source::new(root)
  let stock : Source[String, Int] = Source::new(root)
  let control = @task.task_control(_ => ())
  assert_true(detail.connect(control))
  assert_true(stock.connect(control))
  let cycle = Cycle::new()
  let group = Related::new("item-1", cycle)
  let a = detail.replace("item-1", cycle, false, () => 1).unwrap()
  let b = stock.replace("item-2", cycle, false, () => 2).unwrap()
  a.invalidate()
  b.invalidate()
  assert_eq(a.prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(b.prepare().unwrap().run().apply(), @task.Changed)
  match
    join_related(group.read(detail), group.read(stock), fn(a, b) { a + b })
    .current()
    .view() {
    CurrentBlocked(causes) =>
      assert_true(causes.cause(0) is Some(OtherRequest(_)))
    _ => fail("matching cycles alone do not authorize different item keys")
  }
  let second_group = Related::new("item-2", cycle)
  assert_true(
    join_related(group.read(detail), second_group.read(stock), fn(a, b) {
      a + b
    })
    .current()
    .view()
    is CurrentBlocked(_),
  )
  let later_group = Related::new("item-1", Cycle::new())
  assert_true(
    join_related(group.read(detail), later_group.read(stock), fn(a, b) { a + b })
    .current()
    .view()
    is CurrentBlocked(_),
  )
  root.dispose()
}

///|
async test "inactive currency branch no longer depends on its source" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let currency = @reactive.Signal::new(root, "USD")
  let detail : Source[String, Int] = Source::new(root)
  let rate : Source[String, Int] = Source::new(root)
  let control = @task.task_control(_ => ())
  assert_true(detail.connect(control))
  assert_true(rate.connect(control))
  let item_cycle = Cycle::new()
  let rate_cycle = @reactive.Signal::new(root, Cycle::new())
  let a = detail.replace("one", item_cycle, false, () => 5).unwrap()
  let c = rate.replace("USD", rate_cycle.peek(), false, () => 2).unwrap()
  a.invalidate()
  c.invalidate()
  assert_eq(a.prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(c.prepare().unwrap().run().apply(), @task.Changed)
  let evaluations = Ref(0)
  let value = @reactive.Memo::new(root, () => {
    evaluations.val += 1
    let item = detail.current("one", item_cycle)
    if currency.get() == "JPY" {
      item
    } else {
      join_independent(item, rate.current("USD", rate_cycle.get()), fn(a, c) {
        a * c
      })
    }
  })
  assert_true(value.get().view() is CurrentReady(10, _))
  currency.set("JPY")
  assert_true(value.get().view() is CurrentReady(5, _))
  let after_switch = evaluations.val
  let next_cycle = Cycle::new()
  let next_rate = rate.replace("USD", next_cycle, false, () => 3).unwrap()
  next_rate.invalidate()
  assert_eq(next_rate.prepare().unwrap().run().apply(), @task.Changed)
  rate_cycle.set(next_cycle)
  assert_true(value.get().view() is CurrentReady(5, _))
  assert_eq(evaluations.val, after_switch)
  currency.set("USD")
  assert_true(value.get().view() is CurrentReady(15, _))
  root.dispose()
}
