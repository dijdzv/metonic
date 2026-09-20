///|
test "success and revision" {
  let scope = create()
  assert_eq(field(scope, 0), 0)
  assert_eq(field(scope, 4), 0)
  let id = begin(scope)
  assert_eq(id, 1)
  assert_eq(field(scope, 0), 1)
  assert_eq(field(scope, 4), 1)
  assert_eq(complete(scope, id, 42), true)
  assert_eq(field(scope, 0), 2)
  assert_eq(field(scope, 2), 42)
  assert_eq(field(scope, 4), 2)
}

///|
test "error preserves value" {
  let scope = create()
  let id = begin(scope)
  assert_eq(complete(scope, id, 9), true)
  let next = begin(scope)
  assert_eq(fail(scope, next, 77), true)
  assert_eq(field(scope, 0), 3)
  assert_eq(field(scope, 2), 9)
  assert_eq(field(scope, 3), 77)
}

///|
test "cancel and stale completion" {
  let scope = create()
  let id = begin(scope)
  assert_eq(cancel(scope), true)
  assert_eq(field(scope, 0), 4)
  assert_eq(field(scope, 1), 0)
  assert_eq(complete(scope, id, 1), false)
  assert_eq(cancel(scope), false)
}

///|
test "replacement supersedes old id" {
  let scope = create()
  let old = begin(scope)
  let current = begin(scope)
  assert_eq(current, 2)
  assert_eq(complete(scope, old, 1), false)
  assert_eq(complete(scope, current, 2), true)
}

///|
test "duplicate completion is rejected" {
  let scope = create()
  let id = begin(scope)
  assert_eq(complete(scope, id, 3), true)
  assert_eq(complete(scope, id, 4), false)
  assert_eq(field(scope, 2), 3)
}

///|
test "dispose is terminal" {
  let scope = create()
  let id = begin(scope)
  assert_eq(dispose(scope), true)
  assert_eq(field(scope, 0), 5)
  assert_eq(field(scope, 1), 0)
  assert_eq(field(scope, 5), 1)
  assert_eq(field(scope, 4), 2)
  assert_eq(dispose(scope), false)
  assert_eq(begin(scope), -1)
  assert_eq(complete(scope, id, 1), false)
  assert_eq(fail(scope, id, 1), false)
}
