///|
fn fake_ticket(
  id : Int,
  statuses : Array[UInt],
  payload : Bytes,
  cancelled : Ref[Bool],
  cleared : Ref[Bool],
  cancel_completes : Bool,
) -> ReadbackTicket {
  let index : Ref[Int] = { val: 0, }
  {
    id,
    poll: () => {
      let i = index.val
      if i < statuses.length() {
        index.val += 1
        statuses[i]
      } else {
        0U
      }
    },
    read: () => payload,
    cancel: () => {
      cancelled.val = true
      if cancel_completes && statuses.length() > 0 && statuses[0] == 0U {
        index.val = 0
        statuses[0] = 1U
      }
    },
    clear: () => cleared.val = true,
  }
}

///|
async test "bounded readback fake success and terminal error" {
  let registry : Map[Int, ReadbackTicket] = Map([])
  let cancelled : Ref[Bool] = { val: false, }
  let cleared : Ref[Bool] = { val: false, }
  let ticket = fake_ticket(1, [0U, 1U], b"success!", cancelled, cleared, true)
  assert_eq(run_readback(ticket, registry), b"success!")
  assert_true(registry.is_empty(), msg="success ticket retained")
  assert_true(cleared.val, msg="success ticket not cleared")

  let error_cleared : Ref[Bool] = { val: false, }
  let error_ticket = fake_ticket(
    2,
    [3U],
    b"ignored!",
    cancelled,
    error_cleared,
    true,
  )
  let error_status : UInt = try {
    ignore(run_readback(error_ticket, registry))
    fail("terminal error unexpectedly succeeded")
    0U
  } catch {
    ReadbackFailed::ReadbackFailed(status) => status
    _ => fail("unexpected terminal error")
  } noraise {
    _ => fail("wrong terminal error")
  }
  assert_eq(error_status, 3U)
  assert_true(registry.is_empty(), msg="error ticket retained")
}

///|
async test "bounded readback timeout cleans up" {
  let registry : Map[Int, ReadbackTicket] = Map([])
  let cancelled : Ref[Bool] = { val: false, }
  let cleared : Ref[Bool] = { val: false, }
  let ticket = fake_ticket(3, [0U], b"pending!", cancelled, cleared, true)
  let result = try? run_readback(
    ticket,
    registry,
    timeout_ms=2,
    cleanup_ms=2,
    poll_limit=2,
  )
  match result {
    Ok(_) => fail("timeout unexpectedly succeeded")
    Err(error) => assert_true(error is ReadbackTimeout)
  }
  assert_true(cancelled.val, msg="timeout did not cancel")
  assert_true(cleared.val, msg="timeout did not clear")
  assert_true(registry.is_empty(), msg="cleaned ticket retained")
}

///|
async test "bounded readback permanent pending remains registered" {
  let registry : Map[Int, ReadbackTicket] = Map([])
  let cancelled : Ref[Bool] = { val: false, }
  let cleared : Ref[Bool] = { val: false, }
  let ticket = fake_ticket(4, [0U], b"pending!", cancelled, cleared, false)
  let result = try? run_readback(
    ticket,
    registry,
    timeout_ms=2,
    cleanup_ms=2,
    poll_limit=1,
  )
  match result {
    Ok(_) => fail("permanent pending unexpectedly succeeded")
    Err(error) => assert_true(error is ReadbackTimeout)
  }
  assert_true(cancelled.val, msg="pending ticket was not cancelled")
  assert_true(!cleared.val, msg="permanent pending ticket was cleared")
  assert_true(registry.get(4) is Some(_), msg="pending ticket was lost")
}

///|
async test "bounded readback rejects duplicate ids" {
  let registry : Map[Int, ReadbackTicket] = Map([])
  let cancelled : Ref[Bool] = { val: false, }
  let cleared : Ref[Bool] = { val: false, }
  let first = fake_ticket(7, [0U], b"pending!", cancelled, cleared, false)
  registry.set(7, first)
  let duplicate = fake_ticket(7, [1U], b"duplicate", cancelled, cleared, true)
  let duplicate_status : UInt = try {
    ignore(run_readback(duplicate, registry))
    fail("duplicate id unexpectedly succeeded")
    0U
  } catch {
    ReadbackFailed::ReadbackFailed(status) => status
    _ => fail("unexpected duplicate error")
  } noraise {
    _ => fail("wrong duplicate error")
  }
  assert_eq(duplicate_status, 0U)
}

///|
async test "bounded readback task cancel cleans up and rethrows cancellation" {
  let registry : Map[Int, ReadbackTicket] = Map([])
  let polled : Ref[Bool] = { val: false, }
  let cancel_count : Ref[Int] = { val: 0, }
  let clear_count : Ref[Int] = { val: 0, }
  let status : Ref[UInt] = { val: 0U, }
  let ticket : ReadbackTicket = {
    id: 8,
    poll: () => {
      polled.val = true
      status.val
    },
    read: () => b"cancel!",
    cancel: () => {
      cancel_count.val += 1
      status.val = 1U
    },
    clear: () => clear_count.val += 1,
  }
  @async.with_task_group() <| group => {
    let task = group.spawn() <| () => {
      let result = try? run_readback(
        ticket,
        registry,
        timeout_ms=10000,
        cleanup_ms=1000,
      )
      match result {
        Ok(_) => fail("cancelled readback unexpectedly succeeded")
        Err(error) =>
          assert_true(
            @async.is_cancellation_error(error),
            msg="readback did not rethrow cancellation",
          )
      }
    }
    while !polled.val {
      @async.sleep(1)
    }
    task.cancel()
    task.wait()
  }
  assert_eq(cancel_count.val, 1)
  assert_eq(clear_count.val, 1)
  assert_true(registry.is_empty(), msg="cancelled ticket retained")
}
