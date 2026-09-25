///|
test "driver observation separates admission denial, cancellation and joined cleanup" {
  let driver = @application_task.driver()
  let operation = @task.Operation::new()
  let events : Array[(@task.Operation, @task.DriverEvent)] = []
  assert_true(driver.observe((id, event) => events.push((id, event))))
  assert_false(driver.observe((_, _) => ()))
  let request = @task.cancel(() => (), operation~)
  assert_true(driver.submit(request))
  assert_true(driver.cancel_operation(operation))
  driver.close()
  assert_false(driver.submit(request))
  assert_true(events.all(item => item.0 == operation))
  assert_eq(events.map(item => item.1), [
    @task.RequestAdmitted(1),
    @task.CancelRequested(1),
    @task.CleanupJoined(1),
    @task.RequestDenied(@task.DriverClosed),
  ])
}

///|
async test "driver observation identifies a completion dropped after cancellation" {
  @async.with_timeout(5000, () => {
    let driver = @application_task.driver()
    let operation = @task.Operation::new()
    let events : Array[@task.DriverEvent] = []
    let delivered : Array[@task.Completion] = []
    let ready = @async.CondVar::Cond()
    assert_true(driver.observe((_, event) => events.push(event)))
    assert_true(
      driver.submit(
        @task.replace(
          () => (),
          () => Some(@task.work(() => 7, _ => @task.Changed)),
          operation~,
        ),
      ),
    )
    @async.with_task_group(group => {
      let running = group.spawn(() => {
        driver.run(completion => {
          delivered.push(completion)
          ready.signal()
        })
      })
      while delivered.is_empty() {
        ready.wait()
      }
      assert_true(driver.cancel_operation(operation))
      assert_eq(delivered[0].apply(), @task.Rejected)
      driver.close()
      running.wait()
    })
    assert_true(events.contains(@task.RequestAdmitted(1)))
    assert_true(events.contains(@task.CancelRequested(1)))
    assert_true(events.contains(@task.CleanupJoined(1)))
    assert_true(events.contains(@task.CompletionDropped(1)))
  })
}

///|
test "driver observation explains capacity rejection" {
  let driver = @application_task.driver()
  let denied : Array[@task.AdmissionDenial] = []
  assert_true(
    driver.observe((_, event) => {
      match event {
        @task.RequestDenied(reason) => denied.push(reason)
        _ => ()
      }
    }),
  )
  for _ in 0..<16 {
    assert_true(
      driver.submit(@task.cancel(() => (), operation=@task.Operation::new())),
    )
  }
  assert_false(
    driver.submit(@task.cancel(() => (), operation=@task.Operation::new())),
  )
  assert_eq(denied, [@task.PendingCapacity])
  driver.close()
}

///|
test "closing before run joins queued requests without starting work" {
  let driver = @application_task.driver()
  let events : Array[@task.DriverEvent] = []
  let started = Ref(false)
  assert_true(driver.observe((_, event) => events.push(event)))
  assert_true(
    driver.submit(
      @task.replace(
        () => (),
        () => {
          started.val = true
          None
        },
        operation=@task.Operation::new(),
      ),
    ),
  )
  driver.close()
  assert_false(started.val)
  assert_eq(events, [
    @task.RequestAdmitted(1),
    @task.CancelRequested(1),
    @task.CleanupJoined(1),
  ])
}

///|
async test "replacement reports cleanup join before preparing the next request" {
  @async.with_timeout(5000, () => {
    let driver = @application_task.driver()
    let operation = @task.Operation::new()
    let events : Array[@task.DriverEvent] = []
    let started = Ref(false)
    assert_true(driver.observe((_, event) => events.push(event)))
    assert_true(
      driver.submit(
        @task.replace(
          () => (),
          () => {
            Some(
              @task.work(
                () => {
                  started.val = true
                  @async.sleep(10000)
                  1
                },
                _ => @task.Changed,
              ),
            )
          },
          operation~,
        ),
      ),
    )
    @async.with_task_group(group => {
      let running = group.spawn(() => driver.run(_ => ()))
      while !started.val {
        @async.sleep(10)
      }
      assert_true(driver.submit(@task.cancel(() => (), operation~)))
      while !events.contains(@task.CleanupJoined(1)) {
        @async.sleep(10)
      }
      let cancellation = events.search_by(event => {
        event == @task.CancelRequested(1)
      })
      let joined = events.search_by(event => event == @task.CleanupJoined(1))
      assert_true(cancellation is Some(_))
      assert_true(joined is Some(_))
      assert_true(cancellation.unwrap() < joined.unwrap())
      driver.close()
      running.wait()
    })
  })
}
