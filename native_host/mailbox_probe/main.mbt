///|
extern "C" fn open_mailbox() -> UInt64 = "metonic_mailbox_probe_open"

///|
extern "C" fn close_mailbox() -> Unit = "metonic_mailbox_probe_close"

///|
extern "C" fn send(cookie : UInt64, size : Int) -> Int = "metonic_mailbox_probe_send"

///|
extern "C" fn take_request() -> Int = "metonic_mailbox_probe_take"

///|
extern "C" fn metric(field : Int) -> Int = "metonic_mailbox_probe_metric"

///|
extern "C" fn overlap(cookie : UInt64) -> Int = "metonic_mailbox_probe_overlap"

///|
extern "C" fn join_workers() -> Int = "metonic_mailbox_probe_join"

///|
fn main raise {
  let old = open_mailbox()
  assert_true(old != 0UL)
  for _ in 0..<32 {
    assert_eq(send(old, 8), 1)
  }
  assert_eq(metric(3), 32)
  assert_eq(metric(2), 32)
  assert_eq(send(old, 8), 1)
  assert_eq(metric(1), 1)
  assert_eq(metric(3), 32)
  assert_eq(take_request(), 8)
  assert_eq(send(old, 65536), 1)
  close_mailbox()
  assert_eq(metric(3), 0)
  assert_eq(metric(0), metric(1))
  assert_eq(send(old, 8), 1)
  assert_eq(metric(0), metric(1))
  let current = open_mailbox()
  assert_true(current > old)
  assert_eq(send(old, 8), 1)
  assert_eq(metric(3), 0)
  assert_eq(send(current, 65537), 1)
  assert_eq(metric(3), 0)
  assert_eq(send(current, 65536), 1)
  assert_eq(take_request(), 65536)
  assert_eq(send(current, 0), 1)
  assert_eq(take_request(), 0)
  assert_eq(send(current, -1), 1)
  assert_eq(take_request(), -1)
  assert_eq(take_request(), -2)
  close_mailbox()
  assert_eq(metric(0), metric(1))
  println(
    "MAILBOX_OWNERSHIP_OK capacity value_limits recovery close old_generation",
  )
  for _ in 0..<8 {
    let cookie = open_mailbox()
    assert_true(cookie > current)
    assert_eq(overlap(cookie), 1)
    assert_eq(join_workers(), 1)
    assert_eq(metric(3), 0)
    assert_eq(metric(0), metric(1))
    assert_eq(take_request(), -2)
    let reopened = open_mailbox()
    assert_true(reopened > cookie)
    assert_eq(send(cookie, 8), 1)
    assert_eq(metric(3), 0)
    assert_eq(send(reopened, 8), 1)
    assert_eq(take_request(), 8)
    close_mailbox()
    assert_eq(metric(0), metric(1))
  }
  println("MAILBOX_OVERLAP_OK delivery_close_reopen=8 all_requests_freed")
}
