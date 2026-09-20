///|
pub fn movement_result(
  model : @application.Model,
  id : Int,
  value : Int,
) -> @task.Completion {
  @task.completion(() => {
    if model.complete_movement(id, value) {
      @task.Changed
    } else {
      @task.Rejected
    }
  })
}

///|
pub fn[C : @clock.Clock] movement(
  model : @application.Model,
  clock : C,
) -> @task.Request {
  @task.replace(() => ignore(model.cancel_update()), () => {
    let id = model.begin_update()
    if id <= 0 {
      return None
    }
    let target = model.movement_target()
    Some(
      @task.work(() => @clock.after(clock, 1000, target), value => {
        movement_result(model, id, value).apply()
      }),
    )
  })
}

///|
pub fn[H : @http.Http] user(
  model : @application.Model,
  http : H,
  value : String,
) -> @task.Request {
  @task.replace(() => ignore(model.cancel_update()), () => {
    let id = model.begin_update()
    if id <= 0 {
      return None
    }
    Some(
      @task.work(() => @user_load.load(http, value), result => {
        if model.complete_user(id, result.map(user => user.name)) {
          @task.Changed
        } else {
          @task.Unchanged
        }
      }),
    )
  })
}

///|
pub fn cancel(model : @application.Model) -> @task.Request {
  @task.cancel(() => ignore(model.cancel_update()))
}
