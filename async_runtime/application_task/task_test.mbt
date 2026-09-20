///|
async test "typed results are delivered without mutating application state until applied once" {
  let scope = @task_scope.create()
  let text = Ref("")
  let delivered : Array[@task.Completion] = []
  @async.with_task_group(group => {
    let request = @task.replace(() => ignore(@task_scope.cancel(scope)), () => {
      let id = @task_scope.begin(scope)
      Some(
        @task.work(() => (42, "ready"), result => {
          if @task_scope.complete(scope, id, result.0) {
            text.val = result.1
            @task.Changed
          } else {
            @task.Rejected
          }
        }),
      )
    })
    let task = @application_task.dispatch(request, None, group, result => {
      delivered.push(result)
    })
    task.unwrap().wait()
    assert_eq(text.val, "")
    assert_eq(delivered.length(), 1)
    assert_eq(delivered[0].apply(), @task.Changed)
    assert_eq(text.val, "ready")
    assert_eq(delivered[0].apply(), @task.Unchanged)
  })
}

///|
async test "queued results are rejected after cancellation replacement or disposal" {
  for operation in ["cancel", "replace", "dispose"] {
    let scope = @task_scope.create()
    let delivered : Array[@task.Completion] = []
    @async.with_task_group(group => {
      let first = @task.replace(() => (), () => {
        let id = @task_scope.begin(scope)
        Some(
          @task.work(() => 42, value => {
            if @task_scope.complete(scope, id, value) {
              @task.Changed
            } else {
              @task.Rejected
            }
          }),
        )
      })
      let task = @application_task.dispatch(first, None, group, result => {
        delivered.push(result)
      })
      task.unwrap().wait()
      match operation {
        "replace" => ignore(@task_scope.begin(scope))
        "dispose" => ignore(@task_scope.dispose(scope))
        _ => {
          let canceled = @application_task.dispatch(
            @task.cancel(() => ignore(@task_scope.cancel(scope))),
            task,
            group,
            result => delivered.push(result),
          )
          assert_true(canceled is None)
        }
      }
      assert_eq(delivered[0].apply(), @task.Rejected)
      assert_eq(@task_scope.field(scope, 2), 0)
    })
  }
}

///|
async test "replacement invalidates first and awaits cleanup before preparing new work" {
  let events : Array[String] = []
  let waiting = @async.CondVar::Cond()
  @async.with_task_group(group => {
    let first = @task.replace(() => (), () => {
      Some(
        @task.work(
          () => {
            defer events.push("cleanup")
            waiting.wait()
            1
          },
          _ => @task.Changed,
        ),
      )
    })
    let old = @application_task.dispatch(first, None, group, _ => {
      events.push("old result")
    })
    @async.pause()
    let replacement = @task.replace(() => events.push("invalidate"), () => {
      events.push("prepare")
      Some(@task.work(() => "fresh", _ => @task.Changed))
    })
    let fresh = @application_task.dispatch(replacement, old, group, _ => {
      events.push("fresh result")
    })
    fresh.unwrap().wait()
    assert_eq(events, ["invalidate", "cleanup", "prepare", "fresh result"])
  })
}

///|
suberror WorkFailed derive(Debug)

///|
async test "waiting for a failed task preserves its failure" {
  @async.with_task_group(group => {
    let failed : @async.Task[Unit] = group.spawn(
      () => raise WorkFailed,
      allow_failure=true,
    )
    @async.pause()
    let propagated = try {
      @application_task.cancel_and_wait(Some(failed))
      false
    } catch {
      WorkFailed => true
      other => raise other
    }
    assert_true(propagated)
  })
}
