///|
test "diagnostic history has explicit overflow and does not expose payloads" {
  let registry = TraceRegistry::new(2)
  let state : TraceSource = {
    source_id: 7,
    operation_id: 19,
    owner_id: 3,
    key_id: Some(11),
    cycle_id: Some(5),
    admission_id: 13,
    revision: 17,
    phase: "pending",
    cleanup_pending: [],
  }
  registry.record(PendingTransition, state)
  registry.record(AdmissionRejected, state)
  registry.record(CancellationRequested, state)
  assert_eq(registry.dropped(), 1)
  let events = registry.events()
  assert_eq(events.length(), 2)
  assert_eq(events[0].kind, AdmissionRejected)
  assert_eq(events[1].kind, CancellationRequested)
  assert_eq(events[1].sequence, 3)
  assert_eq(events[1].key_id, Some(11))
  events.clear()
  assert_eq(registry.events().length(), 2)
}

///|
async test "diagnostics explain one source without tracking or retaining a disposed owner" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let registry = TraceRegistry::new(8)
  let source : Source[String, Int] = Source::new(root)
  let owner = registry.track_owner(root, None, ApplicationOwner, 0).unwrap()
  assert_true(
    registry.track_source(source, owner, key => if key == "one" { 1 } else { 2 }),
  )
  assert_false(registry.track_source(source, owner, _ => 0))
  assert_true(source.connect(@task.task_control(_ => ())))
  let cycle = Cycle::new()
  let request = source.replace("one", cycle, false, () => 12).unwrap()
  request.invalidate()
  let pending = registry.sources()
  assert_eq(pending.length(), 1)
  assert_eq(pending[0].owner_id, owner)
  assert_eq(pending[0].operation_id, source.resource.operation.id())
  assert_eq(pending[0].key_id, Some(1))
  assert_eq(pending[0].cycle_id, Some(cycle.id))
  assert_eq(pending[0].phase, "pending")
  assert_eq(request.prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(registry.sources()[0].phase, "ready")
  assert_eq(registry.events().map(event => event.kind), [
    PendingTransition,
    ReadyTransition,
  ])
  root.dispose()
  assert_eq(registry.sources().length(), 0)
  assert_eq(registry.owners().length(), 0)
  assert_eq(registry.events()[2].kind, SourceDisposed)
  assert_eq(registry.events()[3].kind, OwnerDisposed)
}

///|
async test "diagnostics distinguish cancellation and rejected old callbacks" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let registry = TraceRegistry::new(12)
  let source : Source[String, Int] = Source::new(root)
  let owner = registry.track_owner(root, None, ApplicationOwner, 0).unwrap()
  assert_true(registry.track_source(source, owner, _ => 9))
  assert_true(source.connect(@task.task_control(_ => ())))
  let posted : Array[@task.Completion] = []
  let request = source
    .replace_with_progress("one", Cycle::new(), false, post => {
      post(@task.completion(() => @task.Changed))
      2
    })
    .unwrap()
  request.invalidate()
  let finished = request
    .prepare()
    .unwrap()
    .run(post_progress=event => posted.push(event))
  assert_true(source.retire_current())
  assert_eq(posted[0].apply(), @task.Rejected)
  assert_eq(finished.apply(), @task.Rejected)
  assert_eq(request.failure("old error").apply(), @task.Rejected)
  assert_eq(registry.events().map(event => event.kind), [
    PendingTransition,
    CancellationRequested,
    CanceledTransition,
    ProgressRejected,
    CompletionRejected,
    FailureRejected,
  ])
  root.dispose()
}

///|
async test "derived diagnostics retain causes but discard failure payloads" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let child = root.child()
  let registry = TraceRegistry::new(4)
  let app_id = registry.track_owner(root, None, ApplicationOwner, 0).unwrap()
  let child_id = registry
    .track_owner(child, Some(app_id), ComponentOwner, 8)
    .unwrap()
  let source : Source[Int, Int] = Source::new(child)
  assert_true(registry.track_source(source, child_id, key => key))
  assert_true(source.connect(@task.task_control(_ => ())))
  let cycle = Cycle::new()
  let request = source.replace(3, cycle, false, () => 9).unwrap()
  request.invalidate()
  assert_true(registry.observe_derived(22, child_id, source.current(3, cycle)))
  let pending = registry.derived()[0]
  assert_eq(pending.phase, "pending")
  assert_eq(pending.causes.length(), 1)
  assert_true(pending.causes[0] is PendingCause(_))
  assert_eq(
    request.failure("private request content").apply(),
    @task.Failed("private request content"),
  )
  assert_true(registry.observe_derived(22, child_id, source.current(3, cycle)))
  let failed = registry.derived()[0]
  assert_eq(failed.phase, "failed")
  assert_true(failed.causes[0] is FailedCause(_))
  assert_false(@debug.to_string(failed).contains("private request content"))
  assert_true(registry.events().any(event => event.kind == UnexpectedFailure))
  child.dispose()
  assert_eq(registry.derived().length(), 0)
  assert_eq(registry.owners().length(), 1)
  root.dispose()
}

///|
async test "live derived diagnostics sample current state without reactive subscriptions" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let registry = TraceRegistry::new(8)
  let owner = registry.track_owner(root, None, ApplicationOwner, 0).unwrap()
  let source : Source[Int, Int] = Source::new(root)
  assert_true(registry.track_source(source, owner, key => key))
  let cycle = Cycle::new()
  assert_true(
    registry.track_derived(root, 21, owner, () => source.current(4, cycle)),
  )
  let evaluations = Ref(0)
  let inspected = @reactive.Memo::new(root, () => {
    evaluations.val += 1
    registry.derived().length()
  })
  assert_eq(inspected.get(), 1)
  assert_eq(evaluations.val, 1)
  assert_eq(registry.derived()[0].phase, "idle")
  assert_true(source.connect(@task.task_control(_ => ())))
  let request = source.replace(4, cycle, false, () => 8).unwrap()
  request.invalidate()
  assert_eq(registry.derived()[0].phase, "pending")
  assert_eq(inspected.get(), 1)
  assert_eq(evaluations.val, 1)
  assert_eq(request.prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(registry.derived()[0].phase, "ready")
  root.dispose()
  assert_eq(registry.derived().length(), 0)
}

///|
test "driver events join an operation to its source without request contents" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let registry = TraceRegistry::new(4)
  let owner = registry.track_owner(root, None, ApplicationOwner, 0).unwrap()
  let source : Source[Int, Int] = Source::new(root)
  assert_true(registry.track_source(source, owner, key => key))
  registry.driver_event(source.resource.operation, @task.RequestAdmitted(3))
  registry.driver_event(
    source.resource.operation,
    @task.RequestDenied(@task.PendingCapacity),
  )
  registry.driver_event(source.resource.operation, @task.CancelRequested(3))
  assert_eq(registry.sources()[0].cleanup_pending, [3])
  assert_eq(registry.events()[2].cleanup_pending, [3])
  registry.driver_event(source.resource.operation, @task.CleanupJoined(3))
  assert_eq(registry.sources()[0].cleanup_pending, [])
  let events = registry.events()
  assert_eq(events.map(event => event.kind), [
    RequestAdmitted,
    AdmissionRejected,
    CancellationRequested,
    CleanupJoined,
  ])
  assert_eq(events[0].driver_generation, Some(3))
  assert_eq(events[1].denial, Some(@task.PendingCapacity))
  assert_eq(events[3].owner_id, owner)
  assert_eq(events[3].operation_id, source.resource.operation.id())
  root.dispose()
}

///|
async test "diagnostics distinguish expected result failure from unexpected task failure" {
  let root = @reactive.Scope::root(@reactive.Graph::new())
  let registry = TraceRegistry::new(8)
  let owner = registry.track_owner(root, None, ApplicationOwner, 0).unwrap()
  let source : Source[Int, Int] = Source::new(root)
  assert_true(registry.track_source(source, owner, key => key))
  assert_true(source.connect(@task.task_control(_ => ())))
  let expected = source
    .replace_result(
      4,
      Cycle::new(),
      false,
      () => Err("private expected failure"),
      error => error,
    )
    .unwrap()
  expected.invalidate()
  assert_eq(expected.prepare().unwrap().run().apply(), @task.Changed)
  let unexpected = source.replace(5, Cycle::new(), false, () => 5).unwrap()
  unexpected.invalidate()
  assert_eq(
    unexpected.failure("private unexpected failure").apply(),
    @task.Failed("private unexpected failure"),
  )
  assert_eq(registry.events().map(event => event.kind), [
    PendingTransition,
    ExpectedFailure,
    PendingTransition,
    UnexpectedFailure,
  ])
  let snapshot = registry.snapshot_json().stringify()
  assert_false(snapshot.contains("private expected failure"))
  assert_false(snapshot.contains("private unexpected failure"))
  root.dispose()
}
