///|
async test "canceling search does not cancel an independent save" {
  @async.with_timeout(5000, () => {
    let driver = @application_task.driver()
    let save = @task.Operation::new()
    let search = @task.Operation::new()
    let started = @async.CondVar::Cond()
    let finish = @async.CondVar::Cond()
    let found = @async.CondVar::Cond()
    let saved = @async.CondVar::Cond()
    let cleaned = Ref(false)
    let values : Array[Int] = []
    assert_true(
      driver.submit(
        @task.replace(
          () => (),
          () => {
            Some(
              @task.work(
                () => {
                  defer {
                    cleaned.val = true
                  }
                  started.signal()
                  finish.wait()
                  1
                },
                value => {
                  values.push(value)
                  saved.signal()
                  @task.Changed
                },
              ),
            )
          },
          operation=save,
        ),
      ),
    )
    @async.with_task_group(group => {
      let running = group.spawn(() => {
        driver.run(result => ignore(result.apply()))
      })
      started.wait()
      assert_true(
        driver.submit(
          @task.replace(
            () => (),
            () => {
              Some(
                @task.work(() => 2, value => {
                  values.push(value)
                  found.signal()
                  @task.Changed
                }),
              )
            },
            operation=search,
          ),
        ),
      )
      found.wait()
      assert_eq(values, [2])
      assert_false(cleaned.val)
      assert_true(driver.submit(@task.cancel(() => (), operation=search)))
      finish.signal()
      saved.wait()
      assert_eq(values, [2, 1])
      driver.close()
      running.wait()
    })
  })
}

///|
async test "a delayed replacement cleanup does not block another operation" {
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
    let prepared : Array[Int] = []
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
      assert_true(
        driver.submit(
          @task.replace(
            () => (),
            () => {
              prepared.push(1)
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
      cleanup_started.wait()
      assert_true(
        driver.submit(
          @task.replace(
            () => (),
            () => {
              prepared.push(2)
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
      assert_eq(prepared, [])
      cleanup_finish.signal()
      replaced.wait()
      assert_eq(prepared, [2])
      driver.close()
      running.wait()
    })
  })
}

///|
suberror OperationFailure derive(Debug)

///|
async test "a full set of active operations still accepts cancellation and closes all work" {
  @async.with_timeout(5000, () => {
    let driver = @application_task.driver()
    let started = @async.CondVar::Cond()
    let pending = @async.CondVar::Cond()
    let cleaned = Ref(0)
    let operations : Array[@task.Operation] = []
    @async.with_task_group(group => {
      let running = group.spawn(() => {
        driver.run(result => ignore(result.apply()))
      })
      for _ in 0..<16 {
        let operation = @task.Operation::new()
        operations.push(operation)
        assert_true(
          driver.submit(
            @task.replace(
              () => (),
              () => {
                Some(
                  @task.work(
                    () => {
                      defer {
                        cleaned.val += 1
                      }
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
        started.wait()
      }
      assert_true(
        driver.submit(@task.cancel(() => (), operation=operations[0])),
      )
      driver.close()
      running.wait()
      assert_eq(cleaned.val, 16)
    })
  })
}

///|
async test "unexpected failure is delivered and does not stop unrelated or later work" {
  @async.with_timeout(5000, () => {
    let driver = @application_task.driver()
    let operation = @task.Operation::new()
    let ready = @async.CondVar::Cond()
    let results : Array[@task.Outcome] = []
    @async.with_task_group(group => {
      let running = group.spawn(() => {
        driver.run(result => {
          results.push(result.apply())
          ready.signal()
        })
      })
      assert_true(
        driver.submit(
          @task.replace(
            () => (),
            () => {
              Some(
                @task.work(fn() -> Unit raise { raise OperationFailure }, _ => {
                  @task.Changed
                }),
              )
            },
            operation~,
          ),
        ),
      )
      ready.wait()
      assert_true(results[0] is @task.Failed(_))
      for key in [@task.Operation::new(), operation] {
        assert_true(
          driver.submit(
            @task.replace(
              () => (),
              () => Some(@task.work(() => (), _ => @task.Changed)),
              operation=key,
            ),
          ),
        )
        ready.wait()
        assert_eq(results.last(), Some(@task.Changed))
      }
      driver.close()
      running.wait()
    })
  })
}

///|
async test "queued results are invalidated only by their own operation" {
  @async.with_timeout(5000, () => {
    let driver = @application_task.driver()
    let first = @task.Operation::new()
    let second = @task.Operation::new()
    let ready = @async.CondVar::Cond()
    let results : Array[@task.Completion] = []
    @async.with_task_group(group => {
      let running = group.spawn(() => {
        driver.run(result => {
          results.push(result)
          ready.signal()
        })
      })
      for operation in [first, second] {
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
      assert_true(driver.submit(@task.cancel(() => (), operation=first)))
      assert_eq(results[0].apply(), @task.Rejected)
      assert_eq(results[1].apply(), @task.Changed)
      driver.close()
      running.wait()
    })
  })
}

///|
async test "undelivered completions bound admission and applying them frees capacity" {
  @async.with_timeout(5000, () => {
    let driver = @application_task.driver()
    let ready = @async.CondVar::Cond()
    let results : Array[@task.Completion] = []
    @async.with_task_group(group => {
      let running = group.spawn(() => {
        driver.run(result => {
          results.push(result)
          ready.signal()
        })
      })
      for _ in 0..<16 {
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
      }
      let invalidated = Ref(false)
      assert_false(
        driver.submit(
          @task.cancel(
            () => invalidated.val = true,
            operation=@task.Operation::new(),
          ),
        ),
      )
      assert_false(invalidated.val)
      assert_eq(results[0].apply(), @task.Changed)
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
      driver.close()
      running.wait()
      assert_eq(results[16].apply(), @task.Rejected)
    })
  })
}

///|
async test "custom failure handling runs only when a current completion is applied" {
  @async.with_timeout(5000, () => {
    let driver = @application_task.driver()
    let operation = @task.Operation::new()
    let ready = @async.CondVar::Cond()
    let results : Array[@task.Completion] = []
    let handled = Ref(0)
    @async.with_task_group(group => {
      let running = group.spawn(() => {
        driver.run(result => {
          results.push(result)
          ready.signal()
        })
      })
      for _ in 0..<2 {
        assert_true(
          driver.submit(
            @task.replace(
              () => (),
              () => {
                Some(
                  @task.work(fn() -> Unit raise { raise OperationFailure }, _ => {
                    @task.Changed
                  }),
                )
              },
              operation~,
              on_failure=_ => {
                handled.val += 1
                @task.Changed
              },
            ),
          ),
        )
        ready.wait()
      }
      assert_eq(handled.val, 0)
      assert_eq(results[0].apply(), @task.Rejected)
      assert_eq(results[1].apply(), @task.Changed)
      assert_eq(results[1].apply(), @task.Unchanged)
      assert_eq(handled.val, 1)
      driver.close()
      running.wait()
    })
  })
}
