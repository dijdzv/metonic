///|
async test "owned Source diagnosis joins admission, failures, stale completion and disposal" {
  @async.with_timeout(5000, () => {
    let root = @reactive.Scope::root(@reactive.Graph::new())
    let registry = @trace.TraceRegistry::new(48)
    let owner = registry
      .track_owner(root, None, @trace.ApplicationOwner, 0)
      .unwrap()
    let source : @trace.Source[Int, Int] = @trace.Source::new(root)
    assert_true(registry.track_source(source, owner, key => key))
    assert_true(source.connect(@task.task_control(_ => ())))

    let full_driver = @application_task.driver()
    assert_true(
      full_driver.observe((operation, event) => {
        registry.driver_event(operation, event)
      }),
    )
    for _ in 0..<16 {
      assert_true(
        full_driver.submit(
          @task.cancel(() => (), operation=@task.Operation::new()),
        ),
      )
    }
    let denied = source.replace(4, @trace.Cycle::new(), false, () => 4).unwrap()
    assert_false(full_driver.submit(denied))
    let identity = registry.sources()[0]
    let rejection = registry.events().last().unwrap()
    assert_eq(rejection.kind, @trace.AdmissionRejected)
    assert_eq(rejection.denial, Some(@task.PendingCapacity))
    assert_eq(rejection.source_id, identity.source_id)
    assert_eq(rejection.owner_id, owner)
    assert_eq(rejection.operation_id, denied.operation().id())
    assert_eq(identity.phase, "idle")
    full_driver.close()

    let driver = @application_task.driver()
    assert_true(
      driver.observe((operation, event) => {
        registry.driver_event(operation, event)
      }),
    )
    let posted : Array[@task.Completion] = []
    @async.with_task_group(group => {
      let running = group.spawn(() => {
        driver.run(completion => posted.push(completion))
      })
      let expected = source
        .replace_result(
          5,
          @trace.Cycle::new(),
          false,
          () => Err("private expected result"),
          error => error,
        )
        .unwrap()
      assert_true(driver.submit(expected))
      while posted.length() < 1 {
        @async.sleep(10)
      }
      assert_eq(posted[0].apply(), @task.Changed)
      let expected_event = registry.events().last().unwrap()
      assert_eq(expected_event.kind, @trace.ExpectedFailure)
      assert_eq(expected_event.operation_id, expected.operation().id())

      let unexpected = source
        .replace(6, @trace.Cycle::new(), false, fn() -> Int raise {
          raise OperationFailure
        })
        .unwrap()
      assert_true(driver.submit(unexpected))
      while posted.length() < 2 {
        @async.sleep(10)
      }
      assert_true(posted[1].apply() is @task.Failed(_))
      assert_true(
        registry
        .events()
        .any(event => {
          event.kind == @trace.UnexpectedFailure &&
          event.operation_id == unexpected.operation().id()
        }),
      )

      let stale = source
        .replace(7, @trace.Cycle::new(), false, () => 7)
        .unwrap()
      assert_true(driver.submit(stale))
      while posted.length() < 3 {
        @async.sleep(10)
      }
      assert_true(driver.cancel_operation(stale.operation()))
      assert_true(source.retire_current())
      assert_eq(posted[2].apply(), @task.Rejected)
      assert_true(
        registry
        .events()
        .any(event => {
          event.kind == @trace.CompletionRejected &&
          event.operation_id == stale.operation().id()
        }),
      )
      assert_true(
        registry
        .events()
        .any(event => {
          event.kind == @trace.CleanupJoined &&
          event.operation_id == stale.operation().id()
        }),
      )

      let started = Ref(false)
      let waiting = source
        .replace(8, @trace.Cycle::new(), false, () => {
          started.val = true
          @async.sleep(10000)
          8
        })
        .unwrap()
      assert_true(driver.submit(waiting))
      while !started.val {
        @async.sleep(10)
      }
      let admission = registry.sources()[0].admission_id
      assert_true(driver.cancel_operation(waiting.operation()))
      assert_eq(registry.sources()[0].cleanup_pending.length(), 1)
      assert_true(source.retire_current())
      while !registry.sources()[0].cleanup_pending.is_empty() {
        @async.sleep(10)
      }
      let events = registry.events()
      let requested = events
        .search_by(event => {
          event.kind == @trace.CancellationRequested &&
          event.admission_id == admission &&
          event.driver_generation is Some(_)
        })
        .unwrap()
      let joined = events
        .search_by(event => {
          event.kind == @trace.CleanupJoined && event.admission_id == admission
        })
        .unwrap()
      assert_true(requested < joined)
      let snapshot = registry.snapshot_json().stringify()
      assert_false(snapshot.contains("private expected result"))
      driver.close()
      running.wait()
    })
    root.dispose()
    assert_eq(registry.sources().length(), 0)
    assert_eq(registry.owners().length(), 0)
    assert_eq(registry.events().last().unwrap().kind, @trace.OwnerDisposed)
  })
}
