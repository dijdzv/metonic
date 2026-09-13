///|
test "scene pointer includes rectangle edges and moves only outside" {
  for point in [(260, 144), (380, 216), (320, 180)] {
    let (x, y) = point
    reset_state()
    assert_eq(scene_pointer(x, y), 1)
    assert_eq((field(0), field(1), field(4)), (260, 144, 1))
  }
  reset_state()
  assert_eq(scene_pointer(381, 217), 1)
  assert_eq((field(0), field(1), field(4)), (381, 217, 0))
  assert_eq(scene_pointer(-10, -10), 1)
  assert_eq((field(0), field(1)), (0, 0))
  assert_eq(scene_pointer(-10, -10), 0)
}

///|
test "scene keys preserve steps activation and recognized clamped no-op" {
  reset_state()
  for
    step in [
      ("ArrowLeft", 250, 144),
      ("ArrowUp", 250, 134),
      ("ArrowRight", 260, 134),
      ("ArrowDown", 260, 144),
    ] {
    let (key, x, y) = step
    assert_eq(scene_key(key), 1)
    assert_eq((field(0), field(1)), (x, y))
  }
  assert_eq(scene_key(" "), 1)
  assert_eq(field(4), 1)
  assert_eq(scene_key("Enter"), 1)
  assert_eq(field(4), 0)
  let revision = field(5)
  assert_eq(scene_key("a"), -1)
  assert_eq(field(5), revision)
  ignore(move_to(0, 0))
  assert_eq(scene_key("ArrowLeft"), 0)
  assert_eq(scene_key("ArrowUp"), 0)
}
