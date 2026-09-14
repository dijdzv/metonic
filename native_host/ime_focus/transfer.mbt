///|
pub struct Transfer {
  priv mut pointer : (Int, Int, Bool)?
}

///|
pub fn Transfer::new() -> Transfer {
  { pointer: None, }
}

///|
pub fn Transfer::pending(self : Transfer) -> Bool {
  self.pointer is Some(_)
}

///|
pub fn Transfer::request(
  self : Transfer,
  x : Int,
  y : Int,
  extend_selection : Bool,
  complete : () -> Bool,
) -> Unit {
  let already_pending = self.pending()
  self.pointer = Some((x, y, extend_selection))
  if !already_pending && !complete() {
    self.pointer = None
  }
}

///|
pub fn Transfer::cancel(self : Transfer) -> Unit {
  self.pointer = None
}

///|
pub fn Transfer::finish(self : Transfer) -> (Int, Int, Bool)? {
  let pointer = self.pointer
  self.pointer = None
  pointer
}
