///|
test "initial state" {
  let state = create()
  assert_eq(field(state, 0), 260)
  assert_eq(field(state, 1), 144)
  assert_eq(field(state, 2), 120)
  assert_eq(field(state, 3), 72)
  assert_eq(field(state, 4), 0)
  assert_eq(field(state, 5), 0)
  assert_eq(field(state, 6), 640)
  assert_eq(field(state, 7), 360)
}

///|
test "resize clamps position and viewport" {
  let state = create()
  assert_eq(move_to(state, 600, 340), true)
  assert_eq(resize(state, 80, 40), true)
  assert_eq(field(state, 6), 80)
  assert_eq(field(state, 7), 40)
  assert_eq(field(state, 0), 0)
  assert_eq(field(state, 1), 0)
  assert_eq(field(state, 2), 80)
  assert_eq(field(state, 3), 40)
  assert_eq(resize(state, 0, -2), true)
  assert_eq(field(state, 6), 1)
  assert_eq(field(state, 7), 1)
}

///|
test "move clamps to boundaries" {
  let state = create()
  assert_eq(move_to(state, -10, -20), true)
  assert_eq(field(state, 0), 0)
  assert_eq(field(state, 1), 0)
  assert_eq(move_to(state, 999, 999), true)
  assert_eq(field(state, 0), 520)
  assert_eq(field(state, 1), 288)
}

///|
test "same values do not change revision" {
  let state = create()
  assert_eq(resize(state, 640, 360), false)
  assert_eq(move_to(state, 260, 144), false)
  assert_eq(field(state, 5), 0)
}

///|
test "active toggles" {
  let state = create()
  activate(state)
  assert_eq(field(state, 4), 1)
  assert_eq(field(state, 5), 1)
  activate(state)
  assert_eq(field(state, 4), 0)
  assert_eq(field(state, 5), 2)
}
