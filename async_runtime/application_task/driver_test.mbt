///|
async test "closing a driver waits for active work cleanup and rejects further requests" {
  let driver = @application_task.driver()
  let entered = @async.CondVar::Cond()
  let pending = @async.CondVar::Cond()
  let cleaned = Ref(false)
  let delivered : Array[@task.Completion] = []
  let request = @task.replace(() => (), () => {
    Some(
      @task.work(
        () => {
          defer {
            cleaned.val = true
          }
          entered.signal()
          pending.wait()
          1
        },
        _ => @task.Changed,
      ),
    )
  })
  assert_true(driver.submit(request))
  @async.with_task_group(group => {
    let running = group.spawn(() => driver.run(value => delivered.push(value)))
    entered.wait()
    driver.close()
    running.wait()
  })
  assert_true(cleaned.val)
  assert_eq(delivered.length(), 0)
  assert_false(driver.submit(@task.cancel(() => ())))
}

///|
async test "a delivered result cannot mutate state after replacement or close" {
  for close in [false, true] {
    let driver = @application_task.driver()
    let ready = @async.CondVar::Cond()
    let value = Ref(0)
    let delivered : Array[@task.Completion] = []
    assert_true(
      driver.submit(
        @task.replace(() => (), () => {
          Some(
            @task.work(() => 42, result => {
              value.val = result
              @task.Changed
            }),
          )
        }),
      ),
    )
    @async.with_task_group(group => {
      let running = group.spawn(() => {
        driver.run(result => {
          delivered.push(result)
          ready.signal()
        })
      })
      ready.wait()
      if close {
        driver.close()
      } else {
        assert_true(driver.submit(@task.cancel(() => ())))
      }
      assert_eq(delivered[0].apply(), @task.Rejected)
      assert_eq(value.val, 0)
      driver.close()
      running.wait()
    })
  }
}

///|
async test "closing before startup never prepares queued work" {
  let driver = @application_task.driver()
  let prepared = Ref(false)
  assert_true(
    driver.submit(
      @task.replace(() => (), () => {
        prepared.val = true
        None
      }),
    ),
  )
  driver.close()
  driver.run(_ => ())
  assert_false(prepared.val)
}

///|
async test "a current completion applies once and a full queue rejects without invalidating" {
  let driver = @application_task.driver()
  let value = Ref(0)
  let ready = @async.CondVar::Cond()
  for _ in 0..<16 {
    assert_true(
      driver.submit(
        @task.replace(() => (), () => {
          Some(
            @task.work(() => 42, result => {
              value.val = result
              @task.Changed
            }),
          )
        }),
      ),
    )
  }
  assert_false(driver.submit(@task.cancel(() => value.val = -1)))
  @async.with_task_group(group => {
    let running = group.spawn(() => {
      driver.run(result => {
        ignore(result.apply())
        ignore(result.apply())
        ready.signal()
      })
    })
    ready.wait()
    assert_eq(value.val, 42)
    driver.close()
    running.wait()
  })
}

///|
async test "an immediately completed request submitted to a waiting driver is delivered" {
  let driver = @application_task.driver()
  let delivered : Array[@task.Completion] = []
  @async.with_task_group(group => {
    let running = group.spawn(() => driver.run(value => delivered.push(value)))
    @async.sleep(1)
    assert_true(
      driver.submit(
        @task.replace(() => (), () => {
          Some(@task.work(() => 42, _ => @task.Changed))
        }),
      ),
    )
    @async.sleep(1)
    driver.close()
    running.wait()
  })
  assert_eq(delivered.length(), 1)
}
