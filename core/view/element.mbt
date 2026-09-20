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
  x < self.x + self.width &&
  y >= self.y &&
  y < self.y + self.height
}

///|
pub(all) struct Element {
  bounds : Bounds
  text : String
  reference : @semantics.NodeRef?
  focused : Bool
} derive(Eq)
