///|
fn ready_leaf(
  source_id : Int,
  admission_id : Int,
  revision : Int,
  cycle : Cycle,
  value : Int,
) -> Current[Int] {
  let origin : Origin = { source_id, admission_id, revision, cycle, }
  {
    evidence: {
      observations: [{ source_id, origin: Some(origin), phase: LeafReady, }],
      related_mismatch: false,
    },
    value: Some(value),
  }
}

///|
fn inactive_leaf(source_id : Int) -> Current[Int] {
  {
    evidence: {
      observations: [{ source_id, origin: None, phase: LeafIdle, }],
      related_mismatch: false,
    },
    value: None,
  }
}

///|
fn pending_leaf(
  source_id : Int,
  admission_id : Int,
  revision : Int,
  cycle : Cycle,
) -> Current[Int] {
  let origin : Origin = { source_id, admission_id, revision, cycle, }
  {
    evidence: {
      observations: [{ source_id, origin: Some(origin), phase: LeafPending, }],
      related_mismatch: false,
    },
    value: None,
  }
}

///|
fn failed_leaf(
  source_id : Int,
  admission_id : Int,
  revision : Int,
  cycle : Cycle,
  message : String,
) -> Current[Int] {
  let origin : Origin = { source_id, admission_id, revision, cycle, }
  {
    evidence: {
      observations: [
        { source_id, origin: Some(origin), phase: LeafFailed(message), },
      ],
      related_mismatch: false,
    },
    value: None,
  }
}

///|
test "ready idle and pending evidence is independent of join grouping" {
  let cycle = Cycle::new()
  let ready = ready_leaf(11, 101, 1, cycle, 7)
  let idle = inactive_leaf(12)
  let pending = pending_leaf(13, 103, 1, cycle)
  let left = join_independent(
    join_independent(ready, idle, fn(a, b) { a + b }),
    pending,
    fn(a, b) { a + b },
  )
  let right = join_independent(
    ready,
    join_independent(idle, pending, fn(a, b) { a + b }),
    fn(a, b) { a + b },
  )
  assert_eq(left, right)
  match left.view() {
    CurrentPending(causes) => {
      assert_eq(causes.length(), 2)
      assert_true(causes.cause(0) is Some(IdleSource(12)))
      assert_true(causes.cause(1) is Some(PendingSource(_)))
    }
    _ => fail("pending work must survive either join grouping")
  }
}

///|
test "conflicting shared origin survives non-ready intermediate joins" {
  let cycle = Cycle::new()
  let old = ready_leaf(21, 201, 1, cycle, 3)
  let new = ready_leaf(21, 202, 2, cycle, 3)
  let pending = pending_leaf(22, 203, 1, cycle)
  let left = join_independent(
    join_independent(old, new, fn(a, b) { a + b }),
    pending,
    fn(a, b) { a + b },
  )
  let right = join_independent(
    old,
    join_independent(new, pending, fn(a, b) { a + b }),
    fn(a, b) { a + b },
  )
  assert_eq(left, right)
  match left.view() {
    CurrentBlocked(causes) => {
      assert_eq(causes.length(), 2)
      assert_true(causes.cause(0) is Some(OriginConflict(21, _, _)))
      assert_true(causes.cause(1) is Some(PendingSource(_)))
    }
    _ => fail("a stale ready origin cannot become a current value")
  }
  let diamond = join_independent(old, old, fn(a, b) { a + b })
  match diamond.view() {
    CurrentReady(6, origins) => assert_eq(origins.length(), 1)
    _ => fail("a repeated identical leaf should not conflict with itself")
  }
  let progressed = ready_leaf(21, 201, 3, cycle, 4)
  assert_true(
    join_independent(old, progressed, fn(a, b) { a + b }).view()
    is CurrentBlocked(_),
  )
  let third = ready_leaf(21, 204, 4, cycle, 5)
  let all = join_independent(
    join_independent(old, new, fn(a, b) { a + b }),
    third,
    fn(a, b) { a + b },
  )
  let regrouped = join_independent(
    third,
    join_independent(new, old, fn(a, b) { a + b }),
    fn(a, b) { a + b },
  )
  assert_eq(all.view(), regrouped.view())
  match all.view() {
    CurrentBlocked(causes) => assert_eq(causes.length(), 3)
    _ => fail("three revisions of one source have three conflict pairs")
  }
}

///|
test "failure and cancellation keep all leaf causes through nested joins" {
  let cycle = Cycle::new()
  let failure = failed_leaf(31, 301, 1, cycle, "offline")
  let canceled : Current[Int] = {
    evidence: {
      observations: [
        {
          source_id: 32,
          origin: Some({ source_id: 32, admission_id: 302, revision: 1, cycle, }),
          phase: LeafCanceled,
        },
      ],
      related_mismatch: false,
    },
    value: None,
  }
  let pending = pending_leaf(33, 303, 1, cycle)
  let left = join_independent(
    join_independent(failure, canceled, fn(a, b) { a + b }),
    pending,
    fn(a, b) { a + b },
  )
  let right = join_independent(
    failure,
    join_independent(canceled, pending, fn(a, b) { a + b }),
    fn(a, b) { a + b },
  )
  assert_eq(left, right)
  match left.view() {
    CurrentFailed(causes) => {
      assert_eq(causes.length(), 3)
      assert_true(causes.cause(0) is Some(FailedSource(_, "offline")))
      assert_true(causes.cause(1) is Some(CanceledSource(_)))
      assert_true(causes.cause(2) is Some(PendingSource(_)))
    }
    _ => fail("failure must outrank cancellation and pending work")
  }
}

///|
test "related-contract mismatch retains independent failure precedence" {
  let cycle = Cycle::new()
  let failed = failed_leaf(41, 401, 1, cycle, "offline")
  let pending = pending_leaf(42, 402, 1, cycle)
  let old = Related::new("item-1", cycle)
  let other = Related::new("item-2", cycle)
  let related_failed : RelatedCurrent[String, Int] = {
    contract: old,
    current: failed,
  }
  let related_pending : RelatedCurrent[String, Int] = {
    contract: other,
    current: pending,
  }
  match
    join_related(related_failed, related_pending, fn(a, b) { a + b })
    .current()
    .view() {
    CurrentFailed(causes) => {
      assert_eq(causes.length(), 3)
      assert_true(causes.cause(0) is Some(RelatedContractMismatch))
      assert_true(causes.cause(1) is Some(FailedSource(_, "offline")))
      assert_true(causes.cause(2) is Some(PendingSource(_)))
    }
    _ => fail("a mismatched group must not hide an active source failure")
  }
}
