///|
pub fn empty(session : Int, window : Int) -> Tree {
  {
    session,
    window,
    next_id: 1,
    nodes: [],
    next_generation: 1,
    closed: false,
    revision: 0,
  }
}
