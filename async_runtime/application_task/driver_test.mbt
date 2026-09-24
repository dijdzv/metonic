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
test "group admission publishes both reactive invalidations in one batch" {
  let graph = @reactive.Graph::new()
  let scope = @reactive.Scope::root(graph)
  let left = @reactive.Signal::new(scope, 0)
  let right = @reactive.Signal::new(scope, 0)
  let seen : Array[Int] = []
  let _ = @reactive.Binding::new(
    scope,
    fn() { left.get() * 10 + right.get() },
    fn(value) { seen.push(value) },
  )
  let driver = @application_task.driver()
  let first = @task.Operation::new()
  let second = @task.Operation::new()
  let admitted = Ref(0)
  let prepared = Ref(0)
  let requests = [
    @task.cancel(() => left.set(1), operation=first),
    @task.cancel(() => right.set(1), operation=second),
  ]
  let pair = @task.group(requests, apply => graph.batch(apply), on_admitted=() => {
    admitted.val += 1
  })
  requests.clear()
  let exposed = pair.members()
  exposed.clear()
  assert_true(driver.submit(pair, on_prepared=() => prepared.val += 1))
  assert_eq(seen, [0, 11])
  assert_eq(admitted.val, 1)
  let duplicate = @task.group(
    [
      @task.cancel(() => left.set(2), operation=first),
      @task.cancel(() => right.set(2), operation=first),
    ],
    apply => graph.batch(apply),
  )
  assert_false(driver.submit(duplicate))
  assert_eq(seen, [0, 11])
  for _ in 0..<14 {
    assert_true(
      driver.submit(@task.cancel(() => (), operation=@task.Operation::new())),
    )
  }
  assert_false(driver.submit(pair))
  assert_eq(seen, [0, 11])
  driver.close()
  assert_false(driver.submit(pair))
  assert_eq(prepared.val, 1)
  scope.dispose()
}

///|
async test "grouped requests run independently and acknowledge preparation once" {
  @async.with_timeout(5000, () => {
    let driver = @application_task.driver()
    let ready = @async.CondVar::Cond()
    let results : Array[Int] = []
    let outcomes : Array[@task.Outcome] = []
    let prepared = Ref(0)
    let requests : Array[@task.Request] = []
    for value in [1, 2] {
      requests.push(
        @task.replace(
          () => (),
          () => {
            Some(
              @task.work(() => value, result => {
                results.push(result)
                @task.Changed
              }),
            )
          },
          operation=@task.Operation::new(),
        ),
      )
    }
    assert_true(
      driver.submit(@task.group(requests, apply => apply()), on_prepared=() => {
        prepared.val += 1
      }),
    )
    @async.with_task_group(group => {
      let running = group.spawn(() => {
        driver.run(completion => {
          outcomes.push(completion.apply())
          ready.signal()
        })
      })
      while results.length() < 2 {
        ready.wait()
      }
      assert_true(results.contains(1))
      assert_true(results.contains(2))
      assert_eq(outcomes, [@task.Changed, @task.Changed])
      assert_eq(prepared.val, 1)
      driver.close()
      running.wait()
    })
  })
}

///|
async test "closing a grouped submission joins both independent workers" {
  @async.with_timeout(5000, () => {
    let driver = @application_task.driver()
    let entered = @async.CondVar::Cond()
    let blocked = @async.CondVar::Cond()
    let started = Ref(0)
    let cleaned = Ref(0)
    let prepared = Ref(0)
    let requests : Array[@task.Request] = []
    for _ in 0..<2 {
      requests.push(
        @task.replace(
          () => (),
          () => {
            Some(
              @task.work(
                () => {
                  defer {
                    cleaned.val += 1
                  }
                  started.val += 1
                  entered.signal()
                  blocked.wait()
                },
                _ => @task.Changed,
              ),
            )
          },
          operation=@task.Operation::new(),
        ),
      )
    }
    assert_true(
      driver.submit(@task.group(requests, apply => apply()), on_prepared=() => {
        prepared.val += 1
      }),
    )
    @async.with_task_group(group => {
      let running = group.spawn(() => driver.run(_ => ()))
      while started.val < 2 {
        entered.wait()
      }
      assert_eq(prepared.val, 1)
      driver.close()
      running.wait()
    })
    assert_eq(cleaned.val, 2)
    assert_eq(prepared.val, 1)
  })
}

///|
async test "canceling one grouped lane does not reject the other result" {
  @async.with_timeout(5000, () => {
    let driver = @application_task.driver()
    let first = @task.Operation::new()
    let second = @task.Operation::new()
    let ready = @async.CondVar::Cond()
    let completions : Array[@task.Completion] = []
    let first_value = Ref(0)
    let second_value = Ref(0)
    let requests = [
      @task.replace(
        () => (),
        () => {
          Some(
            @task.work(() => 1, result => {
              first_value.val = result
              @task.Changed
            }),
          )
        },
        operation=first,
      ),
      @task.replace(
        () => (),
        () => {
          Some(
            @task.work(() => 2, result => {
              second_value.val = result
              @task.Changed
            }),
          )
        },
        operation=second,
      ),
    ]
    assert_true(driver.submit(@task.group(requests, apply => apply())))
    @async.with_task_group(group => {
      let running = group.spawn(() => {
        driver.run(completion => {
          completions.push(completion)
          ready.signal()
        })
      })
      while completions.length() < 2 {
        ready.wait()
      }
      assert_true(driver.cancel_operation(first))
      let outcomes = completions.map(completion => completion.apply())
      assert_true(outcomes.contains(@task.Rejected))
      assert_true(outcomes.contains(@task.Changed))
      assert_eq(first_value.val, 0)
      assert_eq(second_value.val, 2)
      driver.close()
      running.wait()
    })
  })
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
async test "progress keeps its lane and queued progress rejects after cancellation" {
  @async.with_timeout(5000, () => {
    let driver = @application_task.driver()
    let operation = @task.Operation::new()
    let ready = @async.CondVar::Cond()
    let blocked = @async.CondVar::Cond()
    let delivered : Array[@task.Completion] = []
    let applied = Ref(0)
    assert_true(
      driver.submit(
        @task.replace(
          () => (),
          () => {
            Some(
              @task.work_with_progress(
                post => {
                  for _ in 0..<2 {
                    post(
                      @task.completion(() => {
                        applied.val += 1
                        @task.Changed
                      }),
                    )
                  }
                  blocked.wait()
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
        driver.run(progress => {
          delivered.push(progress)
          ready.signal()
        })
      })
      while delivered.length() < 2 {
        ready.wait()
      }
      assert_eq(delivered[0].apply(), @task.Changed)
      assert_eq(applied.val, 1)
      assert_true(driver.cancel_operation(operation))
      assert_eq(delivered[1].apply(), @task.Rejected)
      assert_eq(applied.val, 1)
      driver.close()
      running.wait()
    })
  })
}

///|
async test "queued progress rejects after replacement or Driver close" {
  for close in [false, true] {
    @async.with_timeout(5000, () => {
      let driver = @application_task.driver()
      let operation = @task.Operation::new()
      let ready = @async.CondVar::Cond()
      let blocked = @async.CondVar::Cond()
      let delivered : Array[@task.Completion] = []
      let applied = Ref(0)
      assert_true(
        driver.submit(
          @task.replace(
            () => (),
            () => {
              Some(
                @task.work_with_progress(
                  post => {
                    post(
                      @task.completion(() => {
                        applied.val += 1
                        @task.Changed
                      }),
                    )
                    blocked.wait()
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
          driver.run(progress => {
            delivered.push(progress)
            ready.signal()
          })
        })
        while delivered.is_empty() {
          ready.wait()
        }
        if close {
          driver.close()
        } else {
          assert_true(
            driver.submit(
              @task.replace(
                () => (),
                () => Some(@task.work(() => (), _ => @task.Changed)),
                operation~,
              ),
            ),
          )
        }
        assert_eq(delivered[0].apply(), @task.Rejected)
        assert_eq(applied.val, 0)
        driver.close()
        running.wait()
      })
    })
  }
}

///|
async test "progress applied after final completion cannot revive its lane" {
  @async.with_timeout(5000, () => {
    let driver = @application_task.driver()
    let ready = @async.CondVar::Cond()
    let delivered : Array[@task.Completion] = []
    let progress_applied = Ref(false)
    assert_true(
      driver.submit(
        @task.replace(() => (), () => {
          Some(
            @task.work_with_progress(
              post => {
                post(
                  @task.completion(() => {
                    progress_applied.val = true
                    @task.Changed
                  }),
                )
              },
              _ => @task.Changed,
            ),
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
      while delivered.length() < 2 {
        ready.wait()
      }
      assert_eq(delivered[1].apply(), @task.Changed)
      assert_eq(delivered[0].apply(), @task.Rejected)
      assert_false(progress_applied.val)
      driver.close()
      running.wait()
    })
  })
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
