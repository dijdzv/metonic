///|
test "accepted completion retains only the latest pointer until termination" {
  let transfer = Transfer::new()
  let requests = Ref(0)
  let complete = () => {
    requests.val += 1
    true
  }
  transfer.request(10, 20, false, complete)
  assert_true(transfer.pending())
  transfer.request(30, 40, true, complete)
  assert_eq(requests.val, 1)
  assert_eq(transfer.finish(), Some((30, 40, true)))
  assert_false(transfer.pending())
  assert_eq(transfer.finish(), None)
}

///|
test "rejected completion cannot replay a pointer but a later request may succeed" {
  let transfer = Transfer::new()
  transfer.request(10, 20, false, () => false)
  assert_false(transfer.pending())
  assert_eq(transfer.finish(), None)
  transfer.request(30, 40, false, () => true)
  assert_eq(transfer.finish(), Some((30, 40, false)))
}

///|
test "focus loss discards pending pointer before a late end event" {
  let transfer = Transfer::new()
  transfer.request(10, 20, true, () => true)
  transfer.cancel()
  assert_eq(transfer.finish(), None)
  assert_false(transfer.pending())
}
