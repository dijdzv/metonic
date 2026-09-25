///|
async test "serial tasks acknowledge one write before admitting the next" {
  let graph = @reactive.Graph::new()
  let root = @reactive.Scope::root(graph)
  let registry = SerialRegistry::new(root)
  assert_true(registry.connect(@task.task_control(_ => ())))
  let applied : Array[(Int, Result[String, String])] = []
  let writer : SerialTask[Int, String, String] = registry.register(
    root,
    value => Ok(value + " saved"),
    (job, result) => applied.push((job.identity, result)),
  )
  assert_true(writer.enqueue(1, "first"))
  assert_false(writer.enqueue(1, "duplicate"))
  let requests : Array[@task.Request] = []
  assert_true(
    registry.reconcile(request => {
      requests.push(request)
      request.invalidate()
      true
    }),
  )
  assert_eq(requests.length(), 1)
  assert_eq(writer.snapshot().active.unwrap().identity, 1)
  assert_true(writer.enqueue(2, "second"))
  assert_eq(writer.snapshot().queued.length(), 1)
  assert_false(registry.reconcile(_ => abort("one document cannot overlap")))
  let first = requests[0].prepare().unwrap().run()
  assert_eq(applied.length(), 0)
  assert_eq(first.apply(), @task.Changed)
  assert_eq(applied, [(1, Ok("first saved"))])
  assert_false(writer.enqueue(1, "first again"))
  assert_true(writer.snapshot().active is None)
  assert_true(
    registry.reconcile(request => {
      requests.push(request)
      request.invalidate()
      true
    }),
  )
  assert_eq(requests.length(), 2)
  assert_eq(writer.snapshot().active.unwrap().identity, 2)
  assert_eq(requests[1].prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(applied, [(1, Ok("first saved")), (2, Ok("second saved"))])
  assert_true(writer.snapshot().queued.is_empty())
  root.dispose()
}

///|
async test "rejected admission stays queued until explicit retry" {
  let graph = @reactive.Graph::new()
  let root = @reactive.Scope::root(graph)
  let registry = SerialRegistry::new(root)
  assert_true(registry.connect(@task.task_control(_ => ())))
  let writer : SerialTask[Int, String, String] = registry.register(
    root,
    value => Ok(value),
    (_, _) => (),
  )
  assert_true(writer.enqueue(7, "waiting"))
  assert_true(registry.reconcile(_ => false))
  assert_true(writer.snapshot().admission_rejected)
  assert_true(writer.snapshot().active is None)
  assert_eq(writer.snapshot().queued.length(), 1)
  assert_false(registry.reconcile(_ => abort("rejected work must not loop")))
  assert_true(writer.retry())
  assert_false(writer.retry())
  let requests : Array[@task.Request] = []
  assert_true(
    registry.reconcile(request => {
      requests.push(request)
      request.invalidate()
      true
    }),
  )
  assert_false(writer.snapshot().admission_rejected)
  assert_eq(writer.snapshot().active.unwrap().identity, 7)
  assert_eq(requests[0].prepare().unwrap().run().apply(), @task.Changed)
  root.dispose()
}

///|
async test "a child can disappear while its app-owned write acknowledges" {
  let graph = @reactive.Graph::new()
  let root = @reactive.Scope::root(graph)
  let child = root.child()
  let text = @reactive.Signal::new(child, "before")
  let registry = SerialRegistry::new(root)
  assert_true(registry.connect(@task.task_control(_ => ())))
  let applied : Array[(Int, String)] = []
  let writer : SerialTask[Int, String, String] = registry.register(
    root,
    value => Ok(value),
    (job, result) => {
      if result is Ok(value) {
        applied.push((job.identity, value))
      }
    },
  )
  assert_true(writer.enqueue(1, text.peek()))
  text.set("edited after enqueue")
  let requests : Array[@task.Request] = []
  assert_true(
    registry.reconcile(request => {
      requests.push(request)
      request.invalidate()
      true
    }),
  )
  let acknowledgement = requests[0].prepare().unwrap().run()
  child.dispose()
  assert_eq(acknowledgement.apply(), @task.Changed)
  assert_eq(applied, [(1, "before")])
  assert_true(writer.snapshot().active is None)
  root.dispose()
}

///|
async test "failure advances the queue and independent lanes do not block" {
  let graph = @reactive.Graph::new()
  let root = @reactive.Scope::root(graph)
  let registry = SerialRegistry::new(root)
  assert_true(registry.connect(@task.task_control(_ => ())))
  let failed : SerialTask[Int, String, String] = registry.register(
    root,
    value => if value == "bad" { Err("disk full") } else { Ok(value) },
    (_, _) => (),
  )
  let other : SerialTask[Int, String, String] = registry.register(
    root,
    value => Ok(value),
    (_, _) => (),
  )
  assert_true(failed.enqueue(1, "bad"))
  assert_true(failed.enqueue(2, "good"))
  assert_true(other.enqueue(1, "independent"))
  let requests : Array[@task.Request] = []
  assert_true(
    registry.reconcile(request => {
      requests.push(request)
      request.invalidate()
      true
    }),
  )
  assert_eq(requests.length(), 2)
  assert_eq(failed.snapshot().active.unwrap().identity, 1)
  assert_eq(other.snapshot().active.unwrap().identity, 1)
  assert_eq(requests[0].prepare().unwrap().run().apply(), @task.Changed)
  assert_true(failed.snapshot().last is Some(Failed(_, "disk full")))
  assert_eq(requests[1].prepare().unwrap().run().apply(), @task.Changed)
  assert_true(other.snapshot().last is Some(Succeeded(_, "independent")))
  assert_true(
    registry.reconcile(request => {
      requests.push(request)
      request.invalidate()
      true
    }),
  )
  assert_eq(requests.length(), 3)
  assert_eq(requests[2].prepare().unwrap().run().apply(), @task.Changed)
  assert_true(failed.snapshot().last is Some(Succeeded(_, "good")))
  root.dispose()
}

///|
async test "cancel and owner disposal reject late write acknowledgements" {
  let graph = @reactive.Graph::new()
  let root = @reactive.Scope::root(graph)
  let owner = root.child()
  let canceled : Array[@task.Operation] = []
  let registry = SerialRegistry::new(root)
  assert_true(registry.connect(@task.task_control(op => canceled.push(op))))
  let applied = Ref(0)
  let writer : SerialTask[Int, String, String] = registry.register(
    owner,
    value => Ok(value),
    (_, _) => applied.val += 1,
  )
  assert_true(writer.enqueue(1, "first"))
  let requests : Array[@task.Request] = []
  assert_true(
    registry.reconcile(request => {
      requests.push(request)
      request.invalidate()
      true
    }),
  )
  let late = requests[0].prepare().unwrap().run()
  assert_true(writer.enqueue(2, "queued"))
  assert_true(writer.cancel())
  assert_eq(canceled.length(), 1)
  assert_true(writer.snapshot().queued.is_empty())
  assert_eq(late.apply(), @task.Rejected)
  assert_eq(applied.val, 0)
  assert_false(registry.reconcile(_ => abort("canceled queue must stay empty")))

  assert_true(writer.enqueue(3, "new"))
  assert_true(
    registry.reconcile(request => {
      requests.push(request)
      request.invalidate()
      true
    }),
  )
  let disposed = requests[1].prepare().unwrap().run()
  owner.dispose()
  assert_eq(canceled.length(), 2)
  assert_eq(disposed.apply(), @task.Rejected)
  assert_eq(applied.val, 0)
  root.dispose()
}
