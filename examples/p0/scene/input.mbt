///|
pub(all) enum Action {
  Move(Int, Int)
  Activate
  Click(Int, Int)
} derive(Debug, Eq)

///|
pub fn dispatch(state : State, action : Action) -> Bool {
  match action {
    Move(dx, dy) => move_to(state, state.x + dx, state.y + dy)
    Activate => {
      activate(state)
      true
    }
    Click(x, y) =>
      if x >= state.x &&
        x < state.x + field(state, 2) &&
        y >= state.y &&
        y < state.y + field(state, 3) {
        activate(state)
        true
      } else {
        false
      }
  }
}
