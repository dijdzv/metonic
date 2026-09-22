///|
pub(all) struct Bounds {
  x : Int
  y : Int
  width : Int
  height : Int
} derive(Eq, Debug)

///|
pub fn Bounds::contains(self : Bounds, x : Int, y : Int) -> Bool {
  x >= self.x &&
  x.to_int64() < self.x.to_int64() + self.width.to_int64() &&
  y >= self.y &&
  y.to_int64() < self.y.to_int64() + self.height.to_int64()
}

///|
pub fn Bounds::intersection(self : Bounds, other : Bounds) -> Bounds? {
  let x = self.x.max(other.x)
  let y = self.y.max(other.y)
  let right = (self.x.to_int64() + self.width.to_int64()).min(
    other.x.to_int64() + other.width.to_int64(),
  )
  let bottom = (self.y.to_int64() + self.height.to_int64()).min(
    other.y.to_int64() + other.height.to_int64(),
  )
  if right <= x.to_int64() || bottom <= y.to_int64() {
    None
  } else {
    Some({
      x,
      y,
      width: (right - x.to_int64()).to_int(),
      height: (bottom - y.to_int64()).to_int(),
    })
  }
}

///|
pub(all) struct Element {
  bounds : Bounds
  text : String
  reference : @semantics.NodeRef?
  focused : Bool
} derive(Eq)
