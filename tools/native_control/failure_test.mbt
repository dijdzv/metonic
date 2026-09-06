///|
async fn failure_message(f : async () -> Json) -> String {
  try {
    ignore(f())
    ""
  } catch {
    error => @debug.to_string(error)
  }
}

///|
async test "native control malformed response closes session" {
  let config = fixture_config(2000, 4)
  with_client(config, async fn(client) {
    assert_true(
      failure_message(async fn() { client.request("malformed") }).contains(
        "malformed",
      ),
    )
    assert_true(expect_failure(async fn() { client.request("snapshot") }))
  })
}

///|
async test "native control unknown response id closes session" {
  let config = fixture_config(2000, 4)
  with_client(config, async fn(client) {
    assert_true(
      failure_message(async fn() { client.request("unknownID") }).contains("id"),
    )
    assert_true(expect_failure(async fn() { client.request("snapshot") }))
  })
}

///|
async test "native control oversized response closes session" {
  let config = fixture_config(2000, 4)
  with_client(config, async fn(client) {
    assert_true(
      failure_message(async fn() {
        client.request(
          "oversize",
          args=Json::object({ "bytes": Json::number(2097152.0) }),
        )
      }).contains("64KiB"),
    )
    assert_true(expect_failure(async fn() { client.request("snapshot") }))
  })
}

///|
async test "native control early child exit closes session" {
  let config = fixture_config(2000, 4)
  with_client(config, async fn(client) {
    assert_true(
      failure_message(async fn() {
        client.request(
          "exit",
          args=Json::object({ "code": Json::number(19.0) }),
        )
      }).contains("exit"),
    )
    assert_true(expect_failure(async fn() { client.request("snapshot") }))
  })
}

///|
async test "native control pending limit preserves first request" {
  let config = fixture_config(2000, 1)
  with_client(config, async fn(client) {
    @async.with_task_group() <| group => {
      let first = group.spawn(() => {
        client.request(
          "delay",
          args=Json::object({ "ms": Json::number(500.0) }),
        )
      })
      @async.with_timeout(1000, async fn() {
        while test_field(client.diagnostics(), "pending") !=
              Some(Json::number(1.0)) {
          @async.sleep(5)
        }
      })
      assert_true(expect_failure(async fn() { client.request("snapshot") }))
      assert_true(has_ok(first.wait()))
    }
    assert_true(has_ok(client.request("snapshot")))
  })
}
