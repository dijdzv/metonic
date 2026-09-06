///|
priv suberror TestFailure {
  Failure(String)
}

///|
async fn fixture_config(timeout_ms : Int, max_pending : Int) -> Config {
  let (code, output) = @process.collect_stdout(
    "where.exe",
    ["node"],
    no_console_window=true,
  )
  if code != 0 {
    raise Failure("where.exe node failed")
  }
  let mut node = ""
  for line in output.text().split("\n") {
    let candidate = line.trim()
    if candidate.length() > 0 && node == "" {
      node = @fs.realpath(candidate)
    }
  }
  if node == "" {
    raise Failure("node executable not found")
  }
  let fixture = @fs.realpath("tools/devtools/fixtures/control-host.mjs")
  Config::new(
    node,
    [fixture],
    "C:/bridge.dll",
    "C:/capture.rgba",
    timeout_ms,
    max_pending,
  )
}

///|
fn test_field(response : Json, key : String) -> Json? {
  match response {
    Json::Object(fields) => fields.get(key)
    _ => None
  }
}

///|
fn has_ok(response : Json) -> Bool {
  match test_field(response, "ok") {
    Some(Json::True) => true
    _ => false
  }
}

///|
fn pending_count(client : Client) -> Int {
  match test_field(client.diagnostics(), "pending") {
    Some(Json::Number(value, ..)) => value.to_int()
    _ => 0
  }
}

///|
async fn expect_failure(f : async () -> Json) -> Bool {
  try {
    ignore(f())
    false
  } catch {
    _ => true
  }
}

///|
async fn expect_capture_failure(client : Client) -> Bool {
  try {
    ignore(client.capture())
    false
  } catch {
    err => @debug.to_string(err).contains("unknown operation: capture")
  }
}

///|
async fn cancellation_request(client : Client) -> Bool {
  try {
    ignore(
      client.request("delay", args=Json::object({ "ms": Json::number(500.0) })),
    )
    false
  } catch {
    err => @async.is_cancellation_error(err)
  }
}

///|
async test "native control fixture snapshot and echo" {
  let config = fixture_config(2000, 4)
  with_client(config, async fn(client) {
    let snapshot = client.request("snapshot")
    assert_true(has_ok(snapshot))
    let echo = client.request(
      "echo",
      args=Json::object({ "value": Json::string("hello") }),
    )
    assert_true(has_ok(echo))
    client.close()
  })
}

///|
async test "native control fixture out of order pending requests" {
  let config = fixture_config(2000, 4)
  with_client(config, async fn(client) {
    @async.with_task_group() <| group => {
      let slow = group.spawn(() => {
        client.request(
          "delay",
          args=Json::object({
            "ms": Json::number(120.0),
            "value": Json::string("slow"),
          }),
        )
      })
      let fast = group.spawn(() => {
        client.request(
          "delay",
          args=Json::object({
            "ms": Json::number(10.0),
            "value": Json::string("fast"),
          }),
        )
      })
      let first = fast.wait()
      let second = slow.wait()
      assert_eq(test_field(first, "value"), Some(Json::string("fast")))
      assert_eq(test_field(second, "value"), Some(Json::string("slow")))
    }
    client.close()
  })
}

///|
async test "native control timeout fails all pending requests" {
  let config = fixture_config(25, 4)
  with_client(config, async fn(client) {
    @async.with_task_group() <| group => {
      let first = group.spawn(() => {
        expect_failure(async fn() {
          client.request(
            "delay",
            args=Json::object({ "ms": Json::number(250.0) }),
          )
        })
      })
      let second = group.spawn(() => {
        expect_failure(async fn() {
          client.request(
            "delay",
            args=Json::object({ "ms": Json::number(250.0) }),
          )
        })
      })
      assert_true(first.wait())
      assert_true(second.wait())
    }
    assert_true(expect_failure(async fn() { client.request("snapshot") }))
  })
}

///|
async test "native control pre-cancel preserves session" {
  let config = fixture_config(2000, 4)
  with_client(config, async fn(client) {
    @async.with_task_group() <| group => {
      let task = group.spawn(() => cancellation_request(client))
      task.cancel()
      assert_true(task.wait())
    }
    assert_true(has_ok(client.request("snapshot")))
  })
}

///|
async test "native control midflight cancellation is fatal" {
  let config = fixture_config(2000, 4)
  with_client(config, async fn(client) {
    @async.with_task_group() <| group => {
      let canceled = group.spawn(() => cancellation_request(client))
      let other = group.spawn(() => {
        expect_failure(async fn() {
          client.request(
            "delay",
            args=Json::object({ "ms": Json::number(500.0) }),
          )
        })
      })
      @async.with_timeout(1000, async fn() {
        while pending_count(client) < 2 {
          @async.sleep(5)
        }
      })
      canceled.cancel()
      assert_true(canceled.wait())
      assert_true(other.wait())
    }
    assert_true(expect_failure(async fn() { client.request("snapshot") }))
  })
}

///|
async test "native control close is concurrent and idempotent" {
  let config = fixture_config(2000, 4)
  with_client(config, async fn(client) {
    @async.with_task_group() <| group => {
      let first = group.spawn(() => {
        client.close()
        ()
      })
      let second = group.spawn(() => {
        client.close()
        ()
      })
      first.wait()
      second.wait()
    }
    client.close()
    assert_true(expect_failure(async fn() { client.request("snapshot") }))
  })
}

///|
async test "native control stderr tail and rejected capture" {
  let config = fixture_config(2000, 4)
  with_client(config, async fn(client) {
    let response = client.request(
      "stderrFlood",
      args=Json::object({ "bytes": Json::number(65536.0) }),
    )
    assert_true(has_ok(response))
    @async.with_timeout(1000, async fn() {
      while (match test_field(client.diagnostics(), "stderr") {
              Some(Json::String(text)) => text.length() < 16384
              _ => true
            }) {
        @async.sleep(5)
      }
    })
    let diagnostics = client.diagnostics()
    match test_field(diagnostics, "stderr") {
      Some(Json::String(text)) => {
        assert_eq(text.length(), 16384)
        assert_true(text.contains("x"))
      }
      _ => assert_true(false)
    }
    assert_true(expect_capture_failure(client))
    assert_true(has_ok(client.request("snapshot")))
  })
}
