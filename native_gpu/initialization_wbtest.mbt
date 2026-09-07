///|
suberror TakeFailure derive(Debug)

///|
fn init_fake_ticket(
  id : Int,
  statuses : Array[UInt],
  state : Ref[Int],
  take_count : Ref[Int],
  discard_count : Ref[Int],
  clear_count : Ref[Int],
  take_fails : Bool,
) -> InitTicket {
  {
    id,
    poll: () => {
      let index = state.val
      if statuses.length() > 0 {
        if index + 1 < statuses.length() {
          state.val += 1
        }
        statuses[index]
      } else {
        0U
      }
    },
    take: () => {
      take_count.val += 1
      if take_fails {
        raise TakeFailure
      }
    },
    discard: () => discard_count.val += 1,
    clear: () => clear_count.val += 1,
  }
}

///|
async test "initialization fake success and terminal error" {
  @async.with_timeout(10000, async fn() {
    let owner = Initialization::new()
    let state : Ref[Int] = { val: 0, }
    let takes : Ref[Int] = { val: 0, }
    let discards : Ref[Int] = { val: 0, }
    let clears : Ref[Int] = { val: 0, }
    let ticket = init_fake_ticket(
      1,
      [0U, 1U],
      state,
      takes,
      discards,
      clears,
      false,
    )
    run_initialization(ticket, owner)
    assert_eq(takes.val, 1)
    assert_eq(discards.val, 0)
    assert_eq(clears.val, 1)
    assert_eq(owner.pending_count(), 0)

    let error_state : Ref[Int] = { val: 0, }
    let error_discards : Ref[Int] = { val: 0, }
    let error_clears : Ref[Int] = { val: 0, }
    let error_ticket = init_fake_ticket(
      2,
      [3U],
      error_state,
      { val: 0, },
      error_discards,
      error_clears,
      false,
    )
    let status : UInt = try {
      run_initialization(error_ticket, owner)
      abort("terminal initialization unexpectedly succeeded")
      0U
    } catch {
      InitializationFailed::InitializationFailed(value) => value
      _ => abort("unexpected terminal initialization error")
    } noraise {
      _ => abort("wrong terminal initialization error")
    }
    assert_eq(status, 3U)
    assert_eq(error_discards.val, 1)
    assert_eq(error_clears.val, 1)
  })
}

///|
async test "initialization timeout and permanent pending reap" {
  @async.with_timeout(10000, async fn() {
    let owner = Initialization::new()
    let state : Ref[Int] = { val: 0, }
    let takes : Ref[Int] = { val: 0, }
    let discards : Ref[Int] = { val: 0, }
    let clears : Ref[Int] = { val: 0, }
    let ticket = init_fake_ticket(
      3,
      [1U],
      state,
      takes,
      discards,
      clears,
      false,
    )
    let status : Bool = try {
      run_initialization(ticket, owner, poll_limit=0)
      true
    } catch {
      InitializationTimeout => false
      _ => abort("unexpected timeout error")
    } noraise {
      _ => abort("timeout raised outside expected error")
    }
    assert_true(!status)
    assert_eq(takes.val, 0)
    assert_eq(discards.val, 1)
    assert_eq(clears.val, 1)
    assert_eq(owner.pending_count(), 0)

    let pending_state : Ref[Int] = { val: 0, }
    let pending_discards : Ref[Int] = { val: 0, }
    let pending_clears : Ref[Int] = { val: 0, }
    let pending_ticket_statuses = [0U]
    let pending_ticket = init_fake_ticket(
      4,
      pending_ticket_statuses,
      pending_state,
      { val: 0, },
      pending_discards,
      pending_clears,
      false,
    )
    try {
      run_initialization(
        pending_ticket,
        owner,
        poll_limit=0,
        cleanup_poll_limit=0,
      )
      assert_true(false, msg="permanent pending unexpectedly succeeded")
    } catch {
      InitializationTimeout => ()
      _ => assert_true(false, msg="unexpected permanent pending error")
    } noraise {
      _ =>
        assert_true(false, msg="pending timeout raised outside expected error")
    }
    assert_eq(owner.pending_count(), 1)
    assert_eq(owner.reap(), 1)
    assert_eq(pending_discards.val, 0)
    assert_eq(pending_clears.val, 0)
    pending_ticket_statuses[0] = 1U
    assert_eq(owner.reap(), 0)
    assert_eq(pending_discards.val, 1)
    assert_eq(pending_clears.val, 1)
    assert_eq(owner.reap(), 0)
  })
}

///|
async test "initialization duplicate id and take failure cleanup" {
  @async.with_timeout(10000, async fn() {
    let owner = Initialization::new()
    let first = init_fake_ticket(
      5,
      [0U],
      { val: 0, },
      { val: 0, },
      { val: 0, },
      { val: 0, },
      false,
    )
    let duplicate = init_fake_ticket(
      5,
      [1U],
      { val: 0, },
      { val: 0, },
      { val: 0, },
      { val: 0, },
      false,
    )
    let duplicate_status : UInt = try {
      run_initialization(first, owner, poll_limit=0, cleanup_poll_limit=0)
      abort("first initialization unexpectedly succeeded")
      0U
    } catch {
      InitializationTimeout => {
        let value : UInt = try {
          run_initialization(duplicate, owner)
          abort("duplicate initialization unexpectedly succeeded")
          0U
        } catch {
          InitializationFailed::InitializationFailed(status) => status
          _ => abort("unexpected duplicate error")
        } noraise {
          _ => abort("wrong duplicate error")
        }
        value
      }
      _ => abort("unexpected first initialization error")
    } noraise {
      _ => abort("duplicate setup raised outside expected error")
    }
    assert_eq(duplicate_status, 0U)
    assert_eq(owner.pending_count(), 1)
    assert_eq(owner.reap(), 1)

    let failure_state : Ref[Int] = { val: 0, }
    let failure_discards : Ref[Int] = { val: 0, }
    let failure_clears : Ref[Int] = { val: 0, }
    let failure_ticket = init_fake_ticket(
      6,
      [1U],
      failure_state,
      { val: 0, },
      failure_discards,
      failure_clears,
      true,
    )
    let failed = try {
      run_initialization(failure_ticket, owner)
      false
    } catch {
      TakeFailure => true
      _ => false
    } noraise {
      _ => false
    }
    assert_true(failed)
    assert_eq(failure_discards.val, 1)
    assert_eq(failure_clears.val, 1)
  })
}

///|
async test "initialization task cancel cleans up exactly once" {
  @async.with_timeout(10000, async fn() {
    let owner = Initialization::new()
    let polled : Ref[Bool] = { val: false, }
    let status : Ref[UInt] = { val: 0U, }
    let takes : Ref[Int] = { val: 0, }
    let discards : Ref[Int] = { val: 0, }
    let clears : Ref[Int] = { val: 0, }
    let ticket : InitTicket = {
      id: 7,
      poll: () => {
        polled.val = true
        status.val
      },
      take: () => takes.val += 1,
      discard: () => discards.val += 1,
      clear: () => clears.val += 1,
    }
    @async.with_task_group() <| group => {
      let task = group.spawn() <| () => {
        try {
          run_initialization(ticket, owner)
          assert_true(
            false,
            msg="cancelled initialization unexpectedly succeeded",
          )
        } catch {
          error =>
            if !@async.is_cancellation_error(error) {
              assert_true(
                false,
                msg="initialization cancellation was not rethrown",
              )
            }
        } noraise {
          _ =>
            assert_true(
              false,
              msg="initialization cancellation escaped expected handler",
            )
        }
      }
      while !polled.val {
        @async.sleep(1)
      }
      task.cancel()
      status.val = 1U
      task.wait()
    }
    assert_eq(takes.val, 0)
    assert_eq(discards.val, 1)
    assert_eq(clears.val, 1)
    assert_eq(owner.pending_count(), 0)
  })
}

///|
async test "initialization active reap leaves cleanup to running task" {
  @async.with_timeout(10000, async fn() {
    let owner = Initialization::new()
    let polled : Ref[Bool] = { val: false, }
    let status : Ref[UInt] = { val: 0U, }
    let takes : Ref[Int] = { val: 0, }
    let discards : Ref[Int] = { val: 0, }
    let clears : Ref[Int] = { val: 0, }
    let ticket : InitTicket = {
      id: 9,
      poll: () => {
        polled.val = true
        status.val
      },
      take: () => takes.val += 1,
      discard: () => discards.val += 1,
      clear: () => clears.val += 1,
    }
    @async.with_task_group() <| group => {
      let task = group.spawn() <| () => { run_initialization(ticket, owner) }
      while !polled.val {
        @async.sleep(1)
      }
      assert_eq(owner.reap(), 1)
      assert_eq(discards.val, 0)
      assert_eq(clears.val, 0)
      status.val = 1U
      assert_eq(owner.reap(), 1)
      assert_eq(discards.val, 0)
      assert_eq(clears.val, 0)
      task.wait()
    }
    assert_eq(takes.val, 1)
    assert_eq(discards.val, 0)
    assert_eq(clears.val, 1)
    assert_eq(owner.reap(), 0)
  })
}

///|
async test "initialization protected drain is invisible to reap" {
  @async.with_timeout(10000, async fn() {
    let owner = Initialization::new()
    let poll_count : Ref[Int] = { val: 0, }
    let cancel_requested : Ref[Bool] = { val: false, }
    let cleanup_started : Ref[Bool] = { val: false, }
    let status : Ref[UInt] = { val: 0U, }
    let takes : Ref[Int] = { val: 0, }
    let discards : Ref[Int] = { val: 0, }
    let clears : Ref[Int] = { val: 0, }
    let ticket : InitTicket = {
      id: 10,
      poll: () => {
        poll_count.val += 1
        if cancel_requested.val {
          cleanup_started.val = true
        }
        status.val
      },
      take: () => takes.val += 1,
      discard: () => discards.val += 1,
      clear: () => clears.val += 1,
    }
    @async.with_task_group() <| group => {
      let task = group.spawn() <| () => {
        try {
          run_initialization(ticket, owner)
          assert_true(
            false,
            msg="cancelled initialization unexpectedly succeeded",
          )
        } catch {
          error =>
            if !@async.is_cancellation_error(error) {
              assert_true(
                false,
                msg="initialization cancellation was not rethrown",
              )
            }
        } noraise {
          _ =>
            assert_true(
              false,
              msg="initialization cancellation escaped expected handler",
            )
        }
      }
      while poll_count.val == 0 {
        @async.sleep(1)
      }
      cancel_requested.val = true
      task.cancel()
      while !cleanup_started.val {
        @async.sleep(1)
      }
      status.val = 1U
      assert_eq(owner.reap(), 1)
      assert_eq(takes.val, 0)
      assert_eq(discards.val, 0)
      assert_eq(clears.val, 0)
      task.wait()
    }
    assert_eq(takes.val, 0)
    assert_eq(discards.val, 1)
    assert_eq(clears.val, 1)
    assert_eq(owner.pending_count(), 0)
  })
}
