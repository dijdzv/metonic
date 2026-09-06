///|
pub struct State {
  mut width : Int
  mut height : Int
  mut x : Int
  mut y : Int
  mut active : Bool
  mut revision : Int
}

///|
pub fn create() -> State {
  {
    width: 640,
    height: 360,
    x: (640 - 120) / 2,
    y: (360 - 72) / 2,
    active: false,
    revision: 0,
  }
}

///|
fn max(a : Int, b : Int) -> Int {
  if a > b {
    a
  } else {
    b
  }
}

///|
fn min(a : Int, b : Int) -> Int {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn clamp(value : Int, low : Int, high : Int) -> Int {
  if value < low {
    low
  } else if value > high {
    high
  } else {
    value
  }
}

///|
pub fn resize(state : State, width : Int, height : Int) -> Bool {
  let next_width = if width < 1 { 1 } else { width }
  let next_height = if height < 1 { 1 } else { height }
  if state.width == next_width && state.height == next_height {
    false
  } else {
    state.width = next_width
    state.height = next_height
    state.x = clamp(state.x, 0, max(0, next_width - 120))
    state.y = clamp(state.y, 0, max(0, next_height - 72))
    state.revision += 1
    true
  }
}

///|
pub fn move_to(state : State, x : Int, y : Int) -> Bool {
  let next_x = clamp(x, 0, max(0, state.width - 120))
  let next_y = clamp(y, 0, max(0, state.height - 72))
  if state.x == next_x && state.y == next_y {
    false
  } else {
    state.x = next_x
    state.y = next_y
    state.revision += 1
    true
  }
}

///|
pub fn activate(state : State) -> Unit {
  state.active = !state.active
  state.revision += 1
}

///|
pub fn field(state : State, index : Int) -> Int {
  match index {
    0 => state.x
    1 => state.y
    2 => min(120, state.width)
    3 => min(72, state.height)
    4 => if state.active { 1 } else { 0 }
    5 => state.revision
    6 => state.width
    7 => state.height
    _ => -1
  }
}
