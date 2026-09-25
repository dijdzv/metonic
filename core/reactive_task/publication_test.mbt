///|
async test "whole ready display is retained only for the same published demand" {
  let graph = @reactive.Graph::new()
  let root = @reactive.Scope::root(graph)
  let registry = PublicationRegistry::new(root)
  let source : Source[String, Int] = Source::new(root)
  assert_true(source.connect(@task.task_control(_ => ())))
  let cycle = @reactive.Signal::new(root, Cycle::new())
  let demand = @reactive.Signal::new(root, "item-1 quantity-1")
  let display = registry.register(root, () => {
    (demand.get(), source.current("item-1", cycle.get()))
  })
  assert_true(display.get() is None)
  assert_true(registry.publish())
  assert_true(display.get().unwrap().current is CurrentIdle(_))
  assert_true(display.get().unwrap().previous is None)
  let first = source.replace("item-1", cycle.peek(), true, () => 7).unwrap()
  assert_false(registry.publish())
  first.invalidate()
  assert_true(registry.publish())
  assert_true(display.get().unwrap().current is CurrentPending(_))
  assert_true(display.get().unwrap().previous is None)
  assert_eq(first.prepare().unwrap().run().apply(), @task.Changed)
  assert_true(registry.publish())
  let first_ready = display.get().unwrap()
  assert_true(first_ready.current is CurrentReady(7, _))
  let first_origin = match first_ready.current {
    CurrentReady(_, provenance) => provenance.origin(0).unwrap()
    _ => abort("published source should be ready")
  }
  let refresh_cycle = Cycle::new()
  let refresh = source.replace("item-1", refresh_cycle, true, () => 8).unwrap()
  graph.batch(() => {
    cycle.set(refresh_cycle)
    refresh.invalidate()
  })
  assert_true(registry.publish())
  match display.get().unwrap() {
    { current: CurrentPending(_), previous: Some(previous), .. } => {
      assert_eq(previous.value, 7)
      assert_eq(previous.provenance.origin(0).unwrap(), first_origin)
    }
    _ => fail("refresh should retain one complete published display")
  }
  assert_eq(refresh.prepare().unwrap().run().apply(), @task.Changed)
  assert_true(registry.publish())
  assert_true(display.get().unwrap().current is CurrentReady(8, _))
  assert_true(display.get().unwrap().previous is None)
  let pending_cycle = Cycle::new()
  let pending = source.replace("item-1", pending_cycle, true, () => 9).unwrap()
  graph.batch(() => {
    cycle.set(pending_cycle)
    pending.invalidate()
  })
  assert_true(registry.publish())
  assert_eq(display.get().unwrap().previous.unwrap().value, 8)
  demand.set("item-1 quantity-2")
  assert_true(registry.publish())
  assert_true(display.get().unwrap().previous is None)
  demand.set("item-1 quantity-1")
  assert_true(registry.publish())
  assert_true(display.get().unwrap().previous is None)
  root.dispose()
}

///|
async test "unsampled transient ready value never becomes publication history" {
  let graph = @reactive.Graph::new()
  let root = @reactive.Scope::root(graph)
  let registry = PublicationRegistry::new(root)
  let source : Source[String, Int] = Source::new(root)
  assert_true(source.connect(@task.task_control(_ => ())))
  let cycle = @reactive.Signal::new(root, Cycle::new())
  let display = registry.register(root, () => {
    ("same demand", source.current("one", cycle.get()))
  })
  let first = source.replace("one", cycle.peek(), true, () => 3).unwrap()
  first.invalidate()
  assert_eq(first.prepare().unwrap().run().apply(), @task.Changed)
  let next_cycle = Cycle::new()
  let next = source.replace("one", next_cycle, true, () => 4).unwrap()
  graph.batch(() => {
    cycle.set(next_cycle)
    next.invalidate()
  })
  assert_true(registry.publish())
  assert_true(display.get().unwrap().current is CurrentPending(_))
  assert_true(display.get().unwrap().previous is None)
  root.dispose()
}

///|
async test "three-source publication retains only a complete same-demand display" {
  let graph = @reactive.Graph::new()
  let root = @reactive.Scope::root(graph)
  let registry = PublicationRegistry::new(root)
  let detail : Source[String, Int] = Source::new(root)
  let stock : Source[String, Int] = Source::new(root)
  let rate : Source[String, Int] = Source::new(root)
  let control = @task.task_control(_ => ())
  assert_true(detail.connect(control))
  assert_true(stock.connect(control))
  assert_true(rate.connect(control))
  let item_cycle = @reactive.Signal::new(root, Cycle::new())
  let rate_cycle = Cycle::new()
  let item = @reactive.Signal::new(root, "item-1")
  let quantity = @reactive.Signal::new(root, 1)
  let currency = @reactive.Signal::new(root, "USD")
  let display = registry.register(root, () => {
    let key = item.get()
    let count = quantity.get()
    let unit = currency.get()
    let group = Related::new(key, item_cycle.get())
    let pair = join_related(group.read(detail), group.read(stock), fn(a, b) {
      a + b
    })
    (
      (key, count, unit),
      join_independent(pair.current(), rate.current(unit, rate_cycle), fn(
        sum,
        multiplier,
      ) {
        sum * multiplier * count
      }),
    )
  })
  let first_a = detail
    .replace("item-1", item_cycle.peek(), false, () => 7)
    .unwrap()
  let first_b = stock
    .replace("item-1", item_cycle.peek(), false, () => 3)
    .unwrap()
  let first_c = rate.replace("USD", rate_cycle, false, () => 2).unwrap()
  graph.batch(() => {
    first_a.invalidate()
    first_b.invalidate()
    first_c.invalidate()
  })
  assert_true(registry.publish())
  assert_true(display.get().unwrap().current is CurrentPending(_))
  assert_true(display.get().unwrap().previous is None)
  assert_eq(first_b.prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(first_c.prepare().unwrap().run().apply(), @task.Changed)
  assert_true(registry.publish())
  assert_true(display.get().unwrap().current is CurrentPending(_))
  assert_eq(first_a.prepare().unwrap().run().apply(), @task.Changed)
  assert_true(registry.publish())
  let complete = display.get().unwrap()
  let first_origin = match complete.current {
    CurrentReady(20, provenance) => {
      assert_eq(provenance.length(), 3)
      provenance.origin(0).unwrap()
    }
    _ => abort("all three sources must publish one complete display")
  }

  let refresh_cycle = Cycle::new()
  let next_a = detail.replace("item-1", refresh_cycle, false, () => 7).unwrap()
  let next_b = stock.replace("item-1", refresh_cycle, false, () => 3).unwrap()
  graph.batch(() => {
    item_cycle.set(refresh_cycle)
    next_a.invalidate()
    next_b.invalidate()
  })
  assert_true(registry.publish())
  assert_eq(display.get().unwrap().previous.unwrap().value, 20)
  assert_eq(display.get().unwrap().previous.unwrap().provenance.length(), 3)
  assert_eq(next_a.prepare().unwrap().run().apply(), @task.Changed)
  assert_true(registry.publish())
  assert_eq(display.get().unwrap().previous.unwrap().value, 20)
  assert_eq(next_b.prepare().unwrap().run().apply(), @task.Changed)
  assert_true(registry.publish())
  match display.get().unwrap().current {
    CurrentReady(20, provenance) => {
      assert_eq(provenance.length(), 3)
      assert_true(provenance.origin(0).unwrap() != first_origin)
    }
    _ => fail("equal payload with new provenance must publish")
  }
  assert_true(display.get().unwrap().previous is None)

  let failed_cycle = Cycle::new()
  let failed_a = detail.replace("item-1", failed_cycle, false, () => 7).unwrap()
  let failed_b = stock.replace("item-1", failed_cycle, false, () => 3).unwrap()
  graph.batch(() => {
    item_cycle.set(failed_cycle)
    failed_a.invalidate()
    failed_b.invalidate()
  })
  assert_true(registry.publish())
  assert_eq(failed_a.failure("offline").apply(), @task.Failed("offline"))
  assert_true(registry.publish())
  assert_true(display.get().unwrap().current is CurrentFailed(_))
  assert_eq(display.get().unwrap().previous.unwrap().value, 20)
  let canceled = stock.cancel().unwrap()
  canceled.invalidate()
  assert_true(registry.publish())
  assert_true(display.get().unwrap().current is CurrentFailed(_))
  assert_eq(display.get().unwrap().previous.unwrap().value, 20)

  let cancel_cycle = Cycle::new()
  let cancel_a = detail.replace("item-1", cancel_cycle, false, () => 7).unwrap()
  let cancel_b = stock.replace("item-1", cancel_cycle, false, () => 3).unwrap()
  graph.batch(() => {
    item_cycle.set(cancel_cycle)
    cancel_a.invalidate()
    cancel_b.invalidate()
  })
  assert_true(registry.publish())
  assert_true(display.get().unwrap().current is CurrentPending(_))
  assert_eq(display.get().unwrap().previous.unwrap().value, 20)
  let cancel_request = stock.cancel().unwrap()
  cancel_request.invalidate()
  assert_true(registry.publish())
  assert_true(display.get().unwrap().current is CurrentCanceled(_))
  assert_eq(display.get().unwrap().previous.unwrap().value, 20)

  quantity.set(2)
  assert_true(registry.publish())
  assert_true(display.get().unwrap().previous is None)
  quantity.set(1)
  assert_true(registry.publish())
  assert_true(display.get().unwrap().previous is None)
  item.set("item-2")
  assert_true(registry.publish())
  assert_true(display.get().unwrap().previous is None)
  currency.set("EUR")
  assert_true(registry.publish())
  assert_true(display.get().unwrap().previous is None)
  root.dispose()
}

///|
async test "independent source may arrive after the related pair" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let registry = PublicationRegistry::new(root)
  let detail : Source[String, Int] = Source::new(root)
  let stock : Source[String, Int] = Source::new(root)
  let rate : Source[String, Int] = Source::new(root)
  let control = @task.task_control(_ => ())
  assert_true(detail.connect(control))
  assert_true(stock.connect(control))
  assert_true(rate.connect(control))
  let item_cycle = Cycle::new()
  let rate_cycle = @reactive.Signal::new(root, Cycle::new())
  let display = registry.register(root, () => {
    let group = Related::new("item-1", item_cycle)
    let pair = join_related(group.read(detail), group.read(stock), fn(a, b) {
      a + b
    })
    (
      "item-1 USD",
      join_independent(pair.current(), rate.current("USD", rate_cycle.get()), fn(
        sum,
        multiplier,
      ) {
        sum * multiplier
      }),
    )
  })
  let a = detail.replace("item-1", item_cycle, false, () => 7).unwrap()
  let b = stock.replace("item-1", item_cycle, false, () => 3).unwrap()
  let c = rate.replace("USD", rate_cycle.peek(), false, () => 2).unwrap()
  a.invalidate()
  b.invalidate()
  c.invalidate()
  assert_true(registry.publish())
  assert_eq(a.prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(b.prepare().unwrap().run().apply(), @task.Changed)
  assert_true(registry.publish())
  assert_true(display.get().unwrap().current is CurrentPending(_))
  assert_true(display.get().unwrap().previous is None)
  assert_eq(c.prepare().unwrap().run().apply(), @task.Changed)
  assert_true(registry.publish())
  assert_true(display.get().unwrap().current is CurrentReady(20, _))
  let new_cycle = Cycle::new()
  let next_c = rate.replace("USD", new_cycle, false, () => 2).unwrap()
  rate_cycle.set(new_cycle)
  next_c.invalidate()
  assert_true(registry.publish())
  assert_true(display.get().unwrap().current is CurrentPending(_))
  assert_eq(display.get().unwrap().previous.unwrap().value, 20)
  assert_eq(next_c.prepare().unwrap().run().apply(), @task.Changed)
  assert_true(registry.publish())
  assert_true(display.get().unwrap().current is CurrentReady(20, _))
  assert_true(display.get().unwrap().previous is None)
  root.dispose()
}

///|
async test "disposing a component with pending work rejects its late result" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let child = root.child()
  let registry = PublicationRegistry::new(root)
  let source : Source[String, Int] = Source::new(child)
  assert_true(source.connect(@task.task_control(_ => ())))
  let cycle = Cycle::new()
  let view = registry.register(child, () => {
    ("one", source.current("one", cycle))
  })
  let request = source.replace("one", cycle, false, () => 5).unwrap()
  request.invalidate()
  assert_true(registry.publish())
  assert_true(view.get().unwrap().current is CurrentPending(_))
  let late = request.prepare().unwrap().run()
  child.dispose()
  assert_false(registry.publish())
  assert_eq(late.apply(), @task.Rejected)
  let replacement = root.child()
  let recreated : Source[String, Int] = Source::new(replacement)
  let new_view = registry.register(replacement, () => {
    ("one", recreated.current("one", cycle))
  })
  assert_true(registry.publish())
  assert_true(new_view.get().unwrap().current is CurrentIdle(_))
  assert_true(new_view.get().unwrap().previous is None)
  root.dispose()
}
