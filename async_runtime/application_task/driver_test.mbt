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

///|
async test "operation control cancels a queued lane without a request slot" {
  @async.with_timeout(5000, () => {
    let driver = @application_task.driver()
    let operations : Array[@task.Operation] = []
    let prepared : Array[Int] = []
    let acknowledgements : Array[Int] = []
    let ready = @async.CondVar::Cond()
    let result_ready = @async.CondVar::Cond()
    let applied = Ref(0)
    for i in 0..<16 {
      let operation = @task.Operation::new()
      operations.push(operation)
      assert_true(
        driver.submit(
          @task.replace(
            () => (),
            () => {
              prepared.push(i)
              Some(@task.work(() => i, _ => @task.Changed))
            },
            operation~,
          ),
          on_prepared=() => {
            acknowledgements.push(i)
            ready.signal()
          },
        ),
      )
    }
    assert_true(driver.cancel_operation(operations[0]))
    assert_false(driver.cancel_operation(operations[0]))
    @async.with_task_group(group => {
      let running = group.spawn(() => {
        driver.run(result => {
          if result.apply() == @task.Changed {
            applied.val += 1
            result_ready.signal()
          }
        })
      })
      while acknowledgements.length() < 16 {
        ready.wait()
      }
      while applied.val < 15 {
        result_ready.wait()
      }
      driver.close()
      running.wait()
    })
    assert_false(prepared.contains(0))
    assert_eq(acknowledgements.length(), 16)
    assert_eq(acknowledgements.filter(i => i == 0).length(), 1)
    assert_eq(applied.val, 15)
  })
}

///|
async test "operation control waits for cleanup before replacement without blocking other lanes" {
  @async.with_timeout(5000, () => {
    let driver = @application_task.driver()
    let operation = @task.Operation::new()
    let other = @task.Operation::new()
    let started = @async.CondVar::Cond()
    let pending = @async.CondVar::Cond()
    let cleanup_started = @async.CondVar::Cond()
    let cleanup_finish = @async.CondVar::Cond()
    let independent = @async.CondVar::Cond()
    let replaced = @async.CondVar::Cond()
    let prepared = Ref(false)
    assert_true(
      driver.submit(
        @task.replace(
          () => (),
          () => {
            Some(
              @task.work(
                () => {
                  defer @async.protect_from_cancel(() => {
                    cleanup_started.signal()
                    cleanup_finish.wait()
                  })
                  started.signal()
                  pending.wait()
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
      let running = group.spawn(() => {
        driver.run(result => ignore(result.apply()))
      })
      started.wait()
      assert_true(driver.cancel_operation(operation))
      cleanup_started.wait()
      assert_true(
        driver.submit(
          @task.replace(
            () => (),
            () => {
              prepared.val = true
              Some(
                @task.work(() => (), _ => {
                  replaced.signal()
                  @task.Changed
                }),
              )
            },
            operation~,
          ),
        ),
      )
      assert_true(
        driver.submit(
          @task.replace(
            () => (),
            () => {
              Some(
                @task.work(() => (), _ => {
                  independent.signal()
                  @task.Changed
                }),
              )
            },
            operation=other,
          ),
        ),
      )
      independent.wait()
      assert_false(prepared.val)
      cleanup_finish.signal()
      replaced.wait()
      assert_true(prepared.val)
      driver.close()
      running.wait()
    })
  })
}

///|
async test "operation control rejects an already posted result and releases its lane" {
  @async.with_timeout(5000, () => {
    let driver = @application_task.driver()
    let operations : Array[@task.Operation] = []
    let results : Array[@task.Completion] = []
    let ready = @async.CondVar::Cond()
    @async.with_task_group(group => {
      let running = group.spawn(() => {
        driver.run(result => {
          results.push(result)
          ready.signal()
        })
      })
      for _ in 0..<16 {
        let operation = @task.Operation::new()
        operations.push(operation)
        assert_true(
          driver.submit(
            @task.replace(
              () => (),
              () => Some(@task.work(() => (), _ => @task.Changed)),
              operation~,
            ),
          ),
        )
        ready.wait()
      }
      assert_true(driver.cancel_operation(operations[0]))
      assert_eq(results[0].apply(), @task.Rejected)
      assert_eq(results[1].apply(), @task.Changed)
      assert_true(
        driver.submit(
          @task.replace(
            () => (),
            () => Some(@task.work(() => (), _ => @task.Changed)),
            operation=@task.Operation::new(),
          ),
        ),
      )
      ready.wait()
      assert_eq(results[16].apply(), @task.Changed)
      driver.close()
      running.wait()
    })
  })
}

///|
async test "repeated short-lived operation cancellation does not exhaust lanes" {
  @async.with_timeout(5000, () => {
    let driver = @application_task.driver()
    let ready = @async.CondVar::Cond()
    let prepared = Ref(0)
    let acknowledged = Ref(0)
    @async.with_task_group(group => {
      let running = group.spawn(() => driver.run(_ => ()))
      for index in 0..<40 {
        let operation = @task.Operation::new()
        assert_true(
          driver.submit(
            @task.replace(
              () => (),
              () => {
                prepared.val += 1
                None
              },
              operation~,
            ),
            on_prepared=() => {
              acknowledged.val += 1
              ready.signal()
            },
          ),
        )
        assert_true(driver.cancel_operation(operation))
        while acknowledged.val <= index {
          ready.wait()
        }
      }
      driver.close()
      running.wait()
    })
    assert_eq(prepared.val, 0)
    assert_eq(acknowledged.val, 40)
  })
}
