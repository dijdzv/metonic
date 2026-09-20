///|
async test "native user operation uses shared response validation over HTTP" {
  for
    (content_type, body, expected) in [
      (
        "application/json",
        "{\"version\":1,\"ok\":true,\"output\":{\"name\":\"Alice\"}}",
        Ok("Alice"),
      ),
      ("text/plain", "{}", Err("invalid_content_type")),
      ("application/json", "{", Err("invalid_json")),
      (
        "application/json",
        "{\"version\":1,\"ok\":false,\"error\":{\"kind\":\"domain\",\"code\":\"not_found\"}}",
        Err("domain:not_found"),
      ),
    ] {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    @async.with_task_group(group => {
      let serving = group.spawn(() => {
        let (connection, _) = server.accept()
        defer connection.close()
        let request = connection.read_request()
        assert_eq(
          request.headers.get(@http.CaseInsensitiveString("Content-Type")),
          Some("application/json"),
        )
        let payload = connection.read_all().text()
        assert_true(payload.contains("users.get.v1"))
        connection.send_response(200, "OK", extra_headers={
          "Content-Type": content_type,
        })
        connection.write(body)
        connection.end_response()
      })
      let result = @rpc_client.get_user("http://\{server.addr}", "1")
      assert_eq(result.map(user => user.name), expected)
      serving.wait()
    })
  }
}

///|
async test "native response byte limit accepts the boundary and rejects excess" {
  let valid = "{\"version\":1,\"ok\":true,\"output\":{\"name\":\"Alice\"}}"
  for size in [65536, 65537] {
    let buffer = StringBuilder()
    buffer.write_string(valid)
    for _ in valid.length()..<size {
      buffer.write_string(" ")
    }
    let body = buffer.to_string()
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    @async.with_task_group(group => {
      let serving = group.spawn(() => {
        let (connection, _) = server.accept()
        defer connection.close()
        ignore(connection.read_request())
        ignore(connection.read_all())
        connection.send_response(200, "OK", extra_headers={
          "Content-Type": "application/json",
        })
        connection.write(body)
        connection.end_response()
      })
      let result = @rpc_client.get_user("http://\{server.addr}", "1")
      assert_eq(
        result.map(user => user.name),
        if size == 65536 {
          Ok("Alice")
        } else {
          Err("response_too_large")
        },
      )
      serving.wait()
    })
  }
}

///|
async test "virtual HTTP deadline closes a native connection with pending body" {
  @async.with_timeout(3000, () => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let clock = @virtual.VirtualClock::new()
    let ready = @cond_var.Cond()
    let headers_sent = Ref(false)
    @async.with_task_group(group => {
      let serving = group.spawn(() => {
        let (connection, _) = server.accept()
        defer connection.close()
        ignore(connection.read_request())
        ignore(connection.read_all())
        connection.send_response(200, "OK", extra_headers={
          "Content-Type": "application/json",
        })
        connection.write("{")
        connection.flush()
        headers_sent.val = true
        ready.signal()
        try {
          ignore(connection.read_request())
          false
        } catch {
          _ => true
        }
      })
      let loading = group.spawn(() => {
        @user_load.load(
          @timed.TimedHttp::{
            transport: @transport.NativeHttp::{ base: "http://\{server.addr}", },
            clock,
            milliseconds: 3000,
          },
          "1",
        )
      })
      while !headers_sent.val {
        ready.wait()
      }
      assert_eq(clock.pending(), 1)
      clock.advance(3000)
      assert_eq(loading.wait().map(user => user.name), Err("timeout"))
      assert_eq(clock.pending(), 0)
      assert_true(serving.wait())
    })
  })
}
