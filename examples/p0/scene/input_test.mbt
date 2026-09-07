///|
test "input actions preserve revision at movement limits" {
  let state = create()
  ignore(move_to(state, 0, 0))
  let revision = field(state, 5)
  assert_false(dispatch(state, Move(-10, 0)))
  assert_eq(field(state, 5), revision)
  assert_true(dispatch(state, Move(10, 0)))
  assert_eq(field(state, 0), 10)
  assert_eq(field(state, 5), revision + 1)
}

///|
test "click uses visible rectangle and excludes right and bottom edges" {
  let state = create()
  ignore(resize(state, 30, 20))
  assert_false(dispatch(state, Click(-1, 0)))
  assert_false(dispatch(state, Click(30, 0)))
  assert_false(dispatch(state, Click(0, 20)))
  assert_eq(field(state, 4), 0)
  assert_true(dispatch(state, Click(29, 19)))
  assert_eq(field(state, 4), 1)
  assert_true(dispatch(state, Activate))
  assert_eq(field(state, 4), 0)
}
