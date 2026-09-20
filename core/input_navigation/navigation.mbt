///|
struct Position {
  reference : @semantics.NodeRef
  revision : Int
  caret : Int
  width : Int
  after : Bool
  preferred_x : Int?
}

///|
pub struct State {
  priv tree : @semantics.Tree
  priv mut positions : Array[Position]
}

///|
pub fn create(tree : @semantics.Tree) -> State {
  { tree, positions: [], }
}

///|
fn State::live(self : State, reference : @semantics.NodeRef) -> Bool {
  match @semantics.node(self.tree, reference) {
    Ok(node) => node.role == @semantics.TextInput
    Err(_) => false
  }
}

///|
fn State::find(
  self : State,
  reference : @semantics.NodeRef,
  caret : Int,
  width : Int,
) -> Position? {
  if !self.live(reference) {
    return None
  }
  for position in self.positions {
    if position.reference == reference &&
      position.revision == @semantics.revision(self.tree) &&
      position.caret == caret &&
      position.width == width {
      return Some(position)
    }
  }
  None
}

///|
pub fn State::reset(self : State) -> Unit {
  self.positions.clear()
}

///|
pub fn State::remember(
  self : State,
  reference : @semantics.NodeRef,
  caret : Int,
  width : Int,
  after : Bool,
  preferred_x : Int?,
) -> Bool {
  if !self.live(reference) || caret < 0 || width <= 0 {
    return false
  }
  self.positions = self.positions.filter(fn(position) {
    position.reference != reference && self.live(position.reference)
  })
  self.positions.push({
    reference,
    revision: @semantics.revision(self.tree),
    caret,
    width,
    after,
    preferred_x,
  })
  true
}

///|
pub fn State::preferred_x(
  self : State,
  reference : @semantics.NodeRef,
  caret : Int,
  width : Int,
) -> Int? {
  match self.find(reference, caret, width) {
    Some(position) => position.preferred_x
    None => None
  }
}

///|
pub fn State::after(
  self : State,
  reference : @semantics.NodeRef,
  caret : Int,
  width : Int,
  composing : Bool,
) -> Bool {
  if composing {
    return false
  }
  match self.find(reference, caret, width) {
    Some(position) => position.after
    None => false
  }
}
