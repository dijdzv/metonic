///|
priv struct PendingDelay {
  mut task : @async.Task[Int]?
  mut live : Bool
}

///|
let task_timers : Map[Int, PendingDelay] = Map([])

///|
let task_epoch : Ref[Int] = Ref(0)

///|
let rejected_callbacks : Ref[Int] = Ref(0)

///|
#export_name("scheduled_task_count")
pub fn scheduled_task_count() -> Int {
  task_timers.length()
}

///|
#export_name("scheduled_task_rejections")
pub fn scheduled_task_rejections() -> Int {
  rejected_callbacks.val
}

///|
#export_name("scheduled_tasks_reset")
pub fn scheduled_tasks_reset() -> Unit {
  for _, pending in task_timers {
    pending.live = false
    if pending.task is Some(task) {
      @async.run_async_main(() => task.cancel())
    }
  }
  task_timers.clear()
  task_epoch.val += 1
}

///|
#export_name("schedule_task")
pub fn schedule_task(delay : Int, value : Int, fail : Int) -> Int {
  if delay < 0 ||
    delay > 5000 ||
    value < 0 ||
    value > 2048 ||
    (fail != 0 && fail != 1) ||
    task_timers.length() >= 16 {
    return 0
  }
  let id = @app.task_begin()
  if id < 0 {
    return 0
  }
  http_cancel()
  let epoch = task_epoch.val
  let pending = PendingDelay::{ task: None, live: true, }
  task_timers.set(id, pending)
  @async.run_async_main(async fn() {
    let result = @async.with_task_group(group => {
      let task = group.spawn(() => {
        if !pending.live {
          return value
        }
        @clock.after(@production_clock.SystemClock::new(), delay, value)
      })
      pending.task = Some(task)
      task.wait()
    }) catch {
      @async.TaskCancelled => return
      _ => {
        if !pending.live || epoch != task_epoch.val {
          return
        }
        task_timers.remove(id)
        ignore(@app.task_fail(id, 7))
        host_notify("metonic-task")
        return
      }
    }
    if !pending.live || epoch != task_epoch.val {
      return
    }
    task_timers.remove(id)
    let accepted = if fail == 1 {
      @app.task_fail(id, 7)
    } else {
      @app.task_complete(id, result)
    }
    if accepted != 1 {
      rejected_callbacks.val += 1
    }
    let event = if accepted == 1 && fail == 0 {
      "metonic-task-render"
    } else {
      "metonic-task"
    }
    host_notify(event)
  })
  1
}
