///|
async test "downstream waits for a coherent pair and ignores unrelated updates" {
  let graph = @reactive.Graph::new()
  let root = @reactive.Scope::root(graph)
  let registry = DownstreamRegistry::new(root)
  let canceled = Ref(0)
  let control = @task.task_control(_ => canceled.val += 1)
  let left : Source[String, Int] = Source::new(root)
  let right : Source[String, Int] = Source::new(root)
  let rate : Source[String, Int] = Source::new(root)
  assert_true(left.connect(control))
  assert_true(right.connect(control))
  assert_true(rate.connect(control))
  assert_true(registry.connect(control))
  let cycle = @reactive.Signal::new(root, Cycle::new())
  let rate_cycle = @reactive.Signal::new(root, Cycle::new())
  let admitted : Array[@task.Request] = []
  let submitted = request => {
    admitted.push(request)
    request.invalidate()
    true
  }
  let downstream = registry.register(
    root,
    () => {
      let related = Related::new("one", cycle.get())
      join_related(related.read(left), related.read(right), fn(a, b) { a + b }).current()
    },
    fn(value : Int) -> Int { value * 2 },
  )
  let display = @reactive.Memo::new(root, () => {
    join_independent(
      downstream.current(),
      rate.current("USD", rate_cycle.get()),
      fn(value, multiplier) { value * multiplier },
    )
  })
  assert_false(registry.reconcile(submitted))
  assert_true(downstream.current().view() is CurrentBlocked(_))
  assert_true(downstream.admission() is AwaitingUpstream)
  let a = left.replace("one", cycle.peek(), false, () => 7).unwrap()
  let b = right.replace("one", cycle.peek(), false, () => 3).unwrap()
  let c = rate.replace("USD", rate_cycle.peek(), false, () => 2).unwrap()
  a.invalidate()
  b.invalidate()
  c.invalidate()
  assert_eq(a.prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(c.prepare().unwrap().run().apply(), @task.Changed)
  assert_false(registry.reconcile(submitted))
  assert_eq(admitted.length(), 0)
  assert_true(downstream.current().view() is CurrentBlocked(_))
  assert_eq(b.prepare().unwrap().run().apply(), @task.Changed)
  assert_true(registry.reconcile(submitted))
  assert_eq(admitted.length(), 1)
  assert_true(downstream.current().view() is CurrentPending(_))
  assert_eq(
    admitted[0].members()[0].prepare().unwrap().run().apply(),
    @task.Changed,
  )
  assert_true(display.get().view() is CurrentReady(40, _))
  let next_rate = Cycle::new()
  let changed = rate.replace("USD", next_rate, false, () => 3).unwrap()
  graph.batch(() => {
    rate_cycle.set(next_rate)
    changed.invalidate()
  })
  assert_false(registry.reconcile(submitted))
  assert_eq(admitted.length(), 1)
  assert_eq(changed.prepare().unwrap().run().apply(), @task.Changed)
  assert_true(display.get().view() is CurrentReady(60, _))
  assert_eq(canceled.val, 0)
  root.dispose()
}

///|
async test "rejected downstream stays blocked until explicit retry" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let registry = DownstreamRegistry::new(root)
  let upstream : Source[String, Int] = Source::new(root)
  let control = @task.task_control(_ => ())
  assert_true(upstream.connect(control))
  assert_true(registry.connect(control))
  let cycle = Cycle::new()
  let downstream = registry.register(
    root,
    () => upstream.current("one", cycle),
    fn(value : Int) -> Int { value + 1 },
  )
  let initial = upstream.replace("one", cycle, false, () => 5).unwrap()
  initial.invalidate()
  assert_eq(initial.prepare().unwrap().run().apply(), @task.Changed)
  let rejected = Ref(0)
  assert_true(
    registry.reconcile(_ => {
      rejected.val += 1
      false
    }),
  )
  assert_eq(rejected.val, 1)
  assert_true(downstream.admission() is Rejected(5, _))
  assert_true(downstream.current().view() is CurrentBlocked(_))
  assert_false(
    registry.reconcile(_ => {
      rejected.val += 1
      false
    }),
  )
  assert_eq(rejected.val, 1)
  assert_true(downstream.retry())
  let admitted : Array[@task.Request] = []
  assert_true(
    registry.reconcile(request => {
      admitted.push(request)
      request.invalidate()
      true
    }),
  )
  assert_eq(admitted.length(), 1)
  assert_true(downstream.current().view() is CurrentPending(_))
  assert_eq(
    admitted[0].members()[0].prepare().unwrap().run().apply(),
    @task.Changed,
  )
  assert_true(downstream.current().view() is CurrentReady(6, _))
  root.dispose()
}

///|
async test "downstream exposes its private Source through bounded diagnostics" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let registry = DownstreamRegistry::new(root)
  let diagnostics = TraceRegistry::new(8)
  let owner = diagnostics.track_owner(root, None, ApplicationOwner, 0).unwrap()
  let upstream : Source[Int, Int] = Source::new(root)
  let cycle = Cycle::new()
  let control = @task.task_control(_ => ())
  assert_true(upstream.connect(control))
  assert_true(registry.connect(control))
  let downstream = registry.register(root, () => upstream.current(7, cycle), fn(
    value : Int,
  ) -> Int {
    value + 1
  })
  assert_true(downstream.track_source(diagnostics, owner, value => value))
  assert_false(downstream.track_source(diagnostics, owner, value => value))
  assert_true(
    diagnostics.track_derived(root, 1, owner, () => downstream.current()),
  )
  let request = upstream.replace(7, cycle, false, () => 4).unwrap()
  request.invalidate()
  assert_eq(request.prepare().unwrap().run().apply(), @task.Changed)
  assert_true(registry.reconcile(_ => false))
  assert_true(downstream.admission() is Rejected(4, _))
  assert_eq(diagnostics.sources()[0].phase, "idle")
  assert_eq(diagnostics.derived()[0].phase, "blocked")
  assert_true(downstream.retry())
  assert_true(
    registry.reconcile(request => {
      request.invalidate()
      true
    }),
  )
  assert_eq(diagnostics.sources()[0].phase, "pending")
  assert_eq(diagnostics.sources()[0].key_id, Some(4))
  root.dispose()
  assert_eq(diagnostics.sources().length(), 0)
}

///|
async test "upstream A to B to A retires every obsolete downstream result" {
  let graph = @reactive.Graph::new()
  let root = @reactive.Scope::root(graph)
  let registry = DownstreamRegistry::new(root)
  let canceled = Ref(0)
  let control = @task.task_control(_ => canceled.val += 1)
  let upstream : Source[String, Int] = Source::new(root)
  assert_true(upstream.connect(control))
  assert_true(registry.connect(control))
  let key = @reactive.Signal::new(root, "A")
  let cycle = @reactive.Signal::new(root, Cycle::new())
  let downstream = registry.register(
    root,
    () => upstream.current(key.get(), cycle.get()),
    fn(value : Int) { value * 10 },
  )
  let admitted : Array[@task.Request] = []
  let submit = request => {
    admitted.push(request)
    request.invalidate()
    true
  }
  let first_upstream = upstream
    .replace("A", cycle.peek(), false, () => 3)
    .unwrap()
  first_upstream.invalidate()
  assert_eq(first_upstream.prepare().unwrap().run().apply(), @task.Changed)
  assert_true(registry.reconcile(submit))
  let stale = admitted[0].members()[0].prepare().unwrap().run()
  assert_true(downstream.current().view() is CurrentPending(_))

  let b_cycle = Cycle::new()
  let second_upstream = upstream.replace("B", b_cycle, false, () => 4).unwrap()
  graph.batch(() => {
    key.set("B")
    cycle.set(b_cycle)
    second_upstream.invalidate()
  })
  assert_true(registry.reconcile(submit))
  assert_true(downstream.current().view() is CurrentBlocked(_))
  assert_eq(canceled.val, 1)
  assert_eq(stale.apply(), @task.Rejected)
  assert_eq(second_upstream.prepare().unwrap().run().apply(), @task.Changed)
  assert_true(registry.reconcile(submit))
  assert_eq(admitted.length(), 2)
  assert_eq(
    admitted[1].members()[0].prepare().unwrap().run().apply(),
    @task.Changed,
  )
  assert_true(downstream.current().view() is CurrentReady(40, _))

  let a_cycle = Cycle::new()
  let third_upstream = upstream.replace("A", a_cycle, false, () => 3).unwrap()
  graph.batch(() => {
    key.set("A")
    cycle.set(a_cycle)
    third_upstream.invalidate()
  })
  assert_true(registry.reconcile(submit))
  assert_eq(third_upstream.prepare().unwrap().run().apply(), @task.Changed)
  assert_true(registry.reconcile(submit))
  assert_eq(admitted.length(), 3)
  assert_eq(
    admitted[2].members()[0].prepare().unwrap().run().apply(),
    @task.Changed,
  )
  assert_true(downstream.current().view() is CurrentReady(30, _))
  root.dispose()
}

///|
async test "disposed owner cannot publish a late downstream value" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let registry = DownstreamRegistry::new(root)
  let upstream : Source[String, Int] = Source::new(root)
  let control = @task.task_control(_ => ())
  assert_true(upstream.connect(control))
  assert_true(registry.connect(control))
  let cycle = Cycle::new()
  let request = upstream.replace("one", cycle, false, () => 2).unwrap()
  request.invalidate()
  assert_eq(request.prepare().unwrap().run().apply(), @task.Changed)
  let child = root.child()
  let _ = registry.register(child, () => upstream.current("one", cycle), fn(
    value : Int,
  ) {
    value + 1
  })
  let admitted : Array[@task.Request] = []
  let submit = request => {
    admitted.push(request)
    request.invalidate()
    true
  }
  assert_true(registry.reconcile(submit))
  let late = admitted[0].members()[0].prepare().unwrap().run()
  child.dispose()
  assert_eq(late.apply(), @task.Rejected)
  assert_false(registry.reconcile(submit))
  let replacement = root.child()
  let fresh = registry.register(
    replacement,
    () => upstream.current("one", cycle),
    fn(value : Int) { value + 2 },
  )
  assert_true(registry.reconcile(submit))
  assert_eq(admitted.length(), 2)
  assert_eq(
    admitted[1].members()[0].prepare().unwrap().run().apply(),
    @task.Changed,
  )
  assert_true(fresh.current().view() is CurrentReady(4, _))
  root.dispose()
}

///|
async test "upstream failure and cancellation remain visible without child work" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let registry = DownstreamRegistry::new(root)
  let upstream : Source[String, Int] = Source::new(root)
  let control = @task.task_control(_ => ())
  assert_true(upstream.connect(control))
  let cycle = @reactive.Signal::new(root, Cycle::new())
  let downstream = registry.register(
    root,
    () => upstream.current("one", cycle.get()),
    fn(value : Int) { value + 1 },
  )
  assert_false(
    registry.reconcile(_ => abort("disconnected registry submitted")),
  )
  assert_true(registry.connect(control))
  let first = upstream.replace("one", cycle.peek(), false, () => 1).unwrap()
  first.invalidate()
  assert_eq(first.failure("offline").apply(), @task.Failed("offline"))
  assert_false(registry.reconcile(_ => abort("failed upstream submitted")))
  assert_true(downstream.current().view() is CurrentFailed(_))
  assert_true(downstream.admission() is AwaitingUpstream)
  let replacement_cycle = Cycle::new()
  let replacement = upstream
    .replace("one", replacement_cycle, false, () => 2)
    .unwrap()
  cycle.set(replacement_cycle)
  replacement.invalidate()
  let cancel = upstream.cancel().unwrap()
  cancel.invalidate()
  assert_false(registry.reconcile(_ => abort("canceled upstream submitted")))
  assert_true(downstream.current().view() is CurrentCanceled(_))
  root.dispose()
}

///|
async test "accepted downstream failure can be retried without losing upstream" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let registry = DownstreamRegistry::new(root)
  let upstream : Source[String, Int] = Source::new(root)
  let control = @task.task_control(_ => ())
  assert_true(upstream.connect(control))
  assert_true(registry.connect(control))
  let cycle = Cycle::new()
  let first = upstream.replace("one", cycle, false, () => 8).unwrap()
  first.invalidate()
  assert_eq(first.prepare().unwrap().run().apply(), @task.Changed)
  let attempts = Ref(0)
  let downstream = registry.register_result(
    root,
    () => upstream.current("one", cycle),
    fn(value : Int) -> Result[Int, String] {
      attempts.val += 1
      if attempts.val == 1 {
        Err("offline")
      } else {
        Ok(value + 1)
      }
    },
    error => error,
  )
  let submitted : Array[@task.Request] = []
  let submit = request => {
    submitted.push(request)
    request.invalidate()
    true
  }
  assert_true(registry.reconcile(submit))
  assert_eq(
    submitted[0].members()[0].prepare().unwrap().run().apply(),
    @task.Changed,
  )
  assert_true(downstream.current().view() is CurrentFailed(_))
  assert_true(downstream.retry())
  assert_true(registry.reconcile(submit))
  assert_eq(submitted.length(), 2)
  assert_eq(
    submitted[1].members()[0].prepare().unwrap().run().apply(),
    @task.Changed,
  )
  match downstream.current().view() {
    CurrentReady(9, provenance) => assert_eq(provenance.length(), 2)
    _ => fail("retry should complete using current upstream provenance")
  }
  root.dispose()
}
