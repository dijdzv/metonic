///|
let task_timers : Map[Int, Int] = Map([])

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
  for _, timer in task_timers {
    @dom.window().clear_timeout(id=timer)
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
  let callback = @dom.Function::new(fn(_) {
    if epoch != task_epoch.val {
      return @dom.JsValue::undefined()
    }
    task_timers.remove(id)
    let accepted = if fail == 1 {
      @app.task_fail(id, 7)
    } else {
      @app.task_complete(id, value)
    }
    if accepted != 1 {
      rejected_callbacks.val += 1
    }
    let event = if accepted == 1 && fail == 0 {
      "metonic-task-render"
    } else {
      "metonic-task"
    }
    ignore(@dom.document().dispatch_event(@dom.Event::new(event)))
    @dom.JsValue::undefined()
  })
  let timer = @dom.window().set_timeout(callback, timeout=delay, [])
  task_timers.set(id, timer)
  1
}
