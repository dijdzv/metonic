///|
async test "sample movement uses injected time and applies only through the completion" {
  let model = @application.create(1, 1)
  let clock = @virtual.VirtualClock::new()
  let x = @scene.field(model.scene, 0)
  let target = model.movement_target()
  let delivered : Array[@task.Completion] = []
  @async.with_task_group(group => {
    let pending = @application_task.dispatch(
      @sample.movement(model, clock),
      None,
      group,
      result => delivered.push(result),
    )
    @async.pause()
    assert_eq(clock.pending(), 1)
    clock.advance(999)
    assert_eq(delivered.length(), 0)
    clock.advance(1)
    pending.unwrap().wait()
    assert_eq(@scene.field(model.scene, 0), x)
    assert_eq(delivered[0].apply(), @task.Changed)
    assert_eq(@scene.field(model.scene, 0), target)
    let next = @application_task.dispatch(
      @sample.movement(model, clock),
      pending,
      group,
      result => delivered.push(result),
    )
    @async.pause()
    let canceled = @application_task.dispatch(
      @sample.cancel(model),
      next,
      group,
      result => delivered.push(result),
    )
    assert_true(canceled is None)
    assert_eq(clock.pending(), 0)
    clock.advance(1000)
    assert_eq(delivered.length(), 1)
    assert_eq(@scene.field(model.scene, 0), target)
  })
}

///|
priv struct ControlledHttp {
  ready : @async.CondVar
  mut released : Bool
  mut requests : Int
  mut cleaned : Int
}

///|
impl @http.Http for ControlledHttp with fn post(self, request) {
  assert_eq(request.path, "/rpc")
  self.requests += 1
  defer {
    self.cleaned += 1
  }
  while !self.released {
    self.ready.wait()
  }
  Ok({
    status: 200,
    content_type: Some("application/json"),
    body: b"{\"version\":1,\"ok\":true,\"output\":{\"name\":\"Alice\"}}",
  })
}

///|
async test "sample HTTP result cannot update a disposed application" {
  let model = @application.create(2, 3)
  let http = ControlledHttp::{
    ready: @async.CondVar::Cond(),
    released: false,
    requests: 0,
    cleaned: 0,
  }
  let delivered : Array[@task.Completion] = []
  @async.with_task_group(group => {
    let pending = @application_task.dispatch(
      @sample.user(model, http, "1"),
      None,
      group,
      result => delivered.push(result),
    )
    @async.pause()
    assert_eq(http.requests, 1)
    assert_eq(model.result, "")
    http.released = true
    http.ready.signal()
    pending.unwrap().wait()
    assert_eq(http.cleaned, 1)
    assert_eq(model.result, "")
    assert_eq(delivered[0].apply(), @task.Changed)
    assert_eq(model.result, "\nAlice")
    let next = @application_task.dispatch(
      @sample.user(model, http, "1"),
      pending,
      group,
      result => delivered.push(result),
    )
    next.unwrap().wait()
    ignore(model.stop())
    assert_eq(delivered[1].apply(), @task.Unchanged)
    assert_eq(model.result, "\nAlice")
    assert_eq(http.cleaned, 2)
  })
}
