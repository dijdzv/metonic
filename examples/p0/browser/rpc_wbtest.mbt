///|
fn receive(id : Int, name : String) -> Int raise Error {
  let body : Json = {
    "version": 1,
    "ok": true,
    "output": { "id": "1", "name": name },
  }
  let bytes = @utf8.encode(body.stringify())
  assert_eq(rpc_begin_input(bytes.length()), 1)
  for byte in bytes {
    assert_eq(rpc_put(byte.to_int()), 1)
  }
  rpc_response(id, 200)
}

///|
test "direct HTTP bytes preserve UTF-8 and reject obsolete responses" {
  reset_state()
  let request = rpc_prepare("日本😀").unwrap()
  assert_true(request.contains("日本😀"))
  let old = task_begin()
  let current = task_begin()
  let body = @utf8.encode(
    "{\"version\":1,\"ok\":true,\"output\":{\"id\":\"1\",\"name\":\"月兎😀\"}}",
  )
  assert_eq(rpc_accept(current, 200, body), 1)
  assert_eq(rpc_accept(old, 200, body), 0)
  assert_eq(@utf8.decode(application.val.result_utf8), "\n月兎😀")
  let canceled = task_begin()
  assert_eq(task_cancel(), 1)
  assert_eq(rpc_accept(canceled, 200, body), 0)
  assert_eq(@utf8.decode(application.val.result_utf8), "\n月兎😀")
}

///|
test "direct HTTP rejects invalid UTF-8 and bodies above the byte budget" {
  reset_state()
  let invalid = task_begin()
  assert_eq(rpc_accept(invalid, 200, b"\xff"), 1)
  assert_true(
    @utf8.decode(application.val.result_utf8).contains("invalid_json"),
  )
  let large = task_begin()
  assert_eq(rpc_accept(large, 200, Bytes::make(65537, b'a')), 1)
  assert_true(
    @utf8.decode(application.val.result_utf8).contains("response_too_large"),
  )
}

///|
test "late HTTP success cannot overwrite a replacement or canceled result" {
  reset_state()
  let old = task_begin()
  let current = task_begin()
  assert_eq(receive(current, "current"), 1)
  assert_eq(receive(old, "obsolete"), 0)
  assert_eq(@utf8.decode(application.val.result_utf8), "\ncurrent")
  let canceled = task_begin()
  assert_eq(task_cancel(), 1)
  assert_eq(receive(canceled, "canceled"), 0)
  assert_eq(@utf8.decode(application.val.result_utf8), "\ncurrent")
  let disposed = task_begin()
  assert_eq(task_dispose(), 1)
  assert_eq(receive(disposed, "disposed"), 0)
  assert_eq(@utf8.decode(application.val.result_utf8), "\ncurrent")
}
