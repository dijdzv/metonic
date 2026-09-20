///|
priv struct Controlled {
  signal : @cond_var.Cond
  mut reply : Result[@capability.Response, @capability.Failure]?
  mut active : Int
  mut closed : Int
}

///|
fn Controlled::new() -> Controlled {
  { signal: @cond_var.Cond(), reply: None, active: 0, closed: 0, }
}

///|
impl @capability.Http for Controlled with fn post(self, _request) {
  self.active += 1
  defer {
    self.active -= 1
    self.closed += 1
  }
  while self.reply is None {
    self.signal.wait()
  }
  self.reply.unwrap()
}

///|
fn Controlled::finish(
  self : Controlled,
  result : Result[@capability.Response, @capability.Failure],
) -> Unit {
  self.reply = Some(result)
  self.signal.signal()
}

///|
fn request() -> @capability.Request {
  {
    path: "/rpc",
    content_type: "application/json",
    body: b"{}",
    response_limit: 65536,
    accepted_content_types: ["application/json"],
  }
}

///|
async fn ready(transport : Controlled, clock : @virtual.VirtualClock) -> Unit {
  for _ in 0..<20 {
    if transport.active == 1 && clock.pending() == 1 {
      return
    }
    @async.pause()
  }
  assert_eq(transport.active, 1)
  assert_eq(clock.pending(), 1)
}

///|
async test "response before deadline returns after timer cleanup" {
  let clock = @virtual.VirtualClock::new()
  let transport = Controlled::new()
  let http = @http.TimedHttp::{ transport, clock, milliseconds: 3000, }
  @async.with_task_group(group => {
    let task = group.spawn(() => @capability.Http::post(http, request()))
    ready(transport, clock)
    clock.advance(2999)
    let response = @capability.Response::{
      status: 200,
      content_type: Some("application/json"),
      body: b"ok",
    }
    transport.finish(Ok(response))
    assert_eq(task.wait(), Ok(response))
    assert_eq(clock.pending(), 0)
    assert_eq(transport.active, 0)
    assert_eq(transport.closed, 1)
  })
}

///|
async test "deadline cancels transport and waits for its cleanup" {
  let clock = @virtual.VirtualClock::new()
  let transport = Controlled::new()
  let http = @http.TimedHttp::{ transport, clock, milliseconds: 3000, }
  @async.with_task_group(group => {
    let task = group.spawn(() => @capability.Http::post(http, request()))
    ready(transport, clock)
    clock.advance(2999)
    assert_eq(task.try_wait(), None)
    clock.advance(1)
    assert_eq(task.wait(), Err(@capability.Timeout))
    assert_eq(clock.pending(), 0)
    assert_eq(transport.active, 0)
    assert_eq(transport.closed, 1)
  })
}

///|
async test "outer cancellation cleans transport and deadline without a result" {
  let clock = @virtual.VirtualClock::new()
  let transport = Controlled::new()
  let http = @http.TimedHttp::{ transport, clock, milliseconds: 3000, }
  let completed = Ref(false)
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      ignore(@capability.Http::post(http, request()))
      completed.val = true
    })
    ready(transport, clock)
    assert_eq(transport.active, 1)
    group.return_immediately(())
  })
  assert_false(completed.val)
  assert_eq(clock.pending(), 0)
  assert_eq(transport.active, 0)
  assert_eq(transport.closed, 1)
}

///|
async test "user operation shares decoding and preserves transport errors" {
  let cases : Array[(@capability.Response, Result[String, String])] = [
    (
      {
        status: 200,
        content_type: Some("application/json"),
        body: b"{\"version\":1,\"ok\":true,\"output\":{\"name\":\"Alice\"}}",
      },
      Ok("Alice"),
    ),
    (
      {
        status: 200,
        content_type: Some("application/json"),
        body: b"{\"version\":1,\"ok\":false,\"error\":{\"kind\":\"domain\",\"code\":\"not_found\"}}",
      },
      Err("domain:not_found"),
    ),
    (
      { status: 200, content_type: None, body: b"{}", },
      Err("invalid_content_type"),
    ),
    (
      { status: 200, content_type: Some("application/json"), body: b"{", },
      Err("invalid_json"),
    ),
  ]
  for (response, expected) in cases {
    let clock = @virtual.VirtualClock::new()
    let transport = Controlled::new()
    let http = @http.TimedHttp::{ transport, clock, milliseconds: 3000, }
    @async.with_task_group(group => {
      let task = group.spawn(() => @user_load.load(http, "1"))
      ready(transport, clock)
      transport.finish(Ok(response))
      assert_eq(task.wait().map(user => user.name), expected)
      assert_eq(clock.pending(), 0)
      assert_eq(transport.closed, 1)
    })
  }
  for
    (failure, expected) in [
      (@capability.Transport, "transport_error"),
      (@capability.ResponseTooLarge, "response_too_large"),
    ] {
    let transport = Controlled::new()
    transport.finish(Err(failure))
    assert_eq(
      @user_load.load(transport, "1").map(user => user.name),
      Err(expected),
    )
  }
}

///|
async test "reversed user responses cannot overwrite a newer operation" {
  let clock = @virtual.VirtualClock::new()
  let old = Controlled::new()
  let fresh = Controlled::new()
  let scope = @task_scope.create()
  let old_id = @task_scope.begin(scope)
  let response = @capability.Response::{
    status: 200,
    content_type: Some("application/json"),
    body: b"{\"version\":1,\"ok\":true,\"output\":{\"name\":\"Alice\"}}",
  }
  @async.with_task_group(group => {
    let first = group.spawn(() => {
      let result = @user_load.load(
        @http.TimedHttp::{ transport: old, clock, milliseconds: 3000, },
        "1",
      )
      assert_true(result is Ok(_))
      @task_scope.complete(scope, old_id, 1)
    })
    ready(old, clock)
    let fresh_id = @task_scope.begin(scope)
    let second = group.spawn(() => {
      let result = @user_load.load(
        @http.TimedHttp::{ transport: fresh, clock, milliseconds: 3000, },
        "2",
      )
      assert_true(result is Ok(_))
      @task_scope.complete(scope, fresh_id, 2)
    })
    fresh.finish(Ok(response))
    assert_true(second.wait())
    old.finish(Ok(response))
    assert_false(first.wait())
    assert_eq(@task_scope.field(scope, 2), 2)
    assert_eq(clock.pending(), 0)
    assert_eq(old.closed, 1)
    assert_eq(fresh.closed, 1)
  })
}

///|
async test "late HTTP success after cancellation or disposal is rejected" {
  for dispose in [false, true] {
    let clock = @virtual.VirtualClock::new()
    let transport = Controlled::new()
    let scope = @task_scope.create()
    let id = @task_scope.begin(scope)
    @async.with_task_group(group => {
      let task = group.spawn(() => {
        let result = @user_load.load(
          @http.TimedHttp::{ transport, clock, milliseconds: 3000, },
          "1",
        )
        assert_true(result is Ok(_))
        @task_scope.complete(scope, id, 1)
      })
      ready(transport, clock)
      if dispose {
        assert_true(@task_scope.dispose(scope))
      } else {
        assert_true(@task_scope.cancel(scope))
      }
      transport.finish(
        Ok({
          status: 200,
          content_type: Some("application/json"),
          body: b"{\"version\":1,\"ok\":true,\"output\":{\"name\":\"Alice\"}}",
        }),
      )
      assert_false(task.wait())
      assert_eq(@task_scope.field(scope, 2), 0)
      assert_eq(clock.pending(), 0)
      assert_eq(transport.closed, 1)
    })
  }
}

///|
async test "invalid and zero deadlines do not start a transport" {
  let clock = @virtual.VirtualClock::new()
  let transport = Controlled::new()
  let zero = @http.TimedHttp::{ transport, clock, milliseconds: 0, }
  assert_eq(@capability.Http::post(zero, request()), Err(@capability.Timeout))
  let invalid = @http.TimedHttp::{ transport, clock, milliseconds: -1, }
  let rejected = try {
    ignore(@capability.Http::post(invalid, request()))
    false
  } catch {
    @clock.InvalidTime => true
    other => raise other
  }
  assert_true(rejected)
  assert_eq(transport.active, 0)
  assert_eq(transport.closed, 0)
  assert_eq(clock.pending(), 0)
}
