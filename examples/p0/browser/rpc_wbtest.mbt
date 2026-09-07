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
test "late HTTP success cannot overwrite a replacement or canceled result" {
  reset_state()
  let old = task_begin()
  let current = task_begin()
  assert_eq(receive(current, "current"), 1)
  assert_eq(receive(old, "obsolete"), 0)
  assert_eq(@utf8.decode(rpc_result.val), "\ncurrent")
  let canceled = task_begin()
  assert_eq(task_cancel(), 1)
  assert_eq(receive(canceled, "canceled"), 0)
  assert_eq(@utf8.decode(rpc_result.val), "\ncurrent")
  let disposed = task_begin()
  assert_eq(task_dispose(), 1)
  assert_eq(receive(disposed, "disposed"), 0)
  assert_eq(@utf8.decode(rpc_result.val), "\ncurrent")
}
