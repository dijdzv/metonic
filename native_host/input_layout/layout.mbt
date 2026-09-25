///|
struct Input {
  reference : @semantics.NodeRef
  engine : @raster.Engine
  single_line : Bool
  mut scroll_x : Int
  mut scroll_y : Int
}

///|
pub struct Registry {
  priv tree : @semantics.Tree
  priv mut inputs : Array[Input]
}

///|
pub fn create(tree : @semantics.Tree) -> Registry {
  { tree, inputs: [], }
}

///|
fn Registry::live(self : Registry, reference : @semantics.NodeRef) -> Bool {
  match @semantics.node(self.tree, reference) {
    Ok(node) => node.role == @semantics.TextInput
    Err(_) => false
  }
}

///|
fn Registry::find(self : Registry, reference : @semantics.NodeRef) -> Input? {
  if !self.live(reference) {
    return None
  }
  for input in self.inputs {
    if input.reference == reference {
      return Some(input)
    }
  }
  None
}

///|
pub fn Registry::register(
  self : Registry,
  reference : @semantics.NodeRef,
  font : Bytes,
  single_line : Bool,
) -> Bool {
  if !self.live(reference) || self.find(reference) is Some(_) {
    return false
  }
  guard @raster.create(font) is Some(engine) else { return false }
  self.inputs = self.inputs.filter(input => self.live(input.reference))
  self.inputs.push({ reference, engine, single_line, scroll_x: 0, scroll_y: 0, })
  true
}

///|
pub fn Registry::engine(
  self : Registry,
  reference : @semantics.NodeRef,
) -> @raster.Engine? {
  self.find(reference).map(input => input.engine)
}

///|
pub fn Registry::single_line(
  self : Registry,
  reference : @semantics.NodeRef,
) -> Bool? {
  self.find(reference).map(input => input.single_line)
}

///|
pub fn Registry::scroll_x(
  self : Registry,
  reference : @semantics.NodeRef,
) -> Int {
  self.find(reference).map(input => input.scroll_x).unwrap_or(0)
}

///|
pub fn Registry::scroll_y(
  self : Registry,
  reference : @semantics.NodeRef,
) -> Int {
  self.find(reference).map(input => input.scroll_y).unwrap_or(0)
}

///|
pub fn Registry::prepare_single_line(
  self : Registry,
  reference : @semantics.NodeRef,
  text : String,
  width : Int,
  active_caret : Int?,
  theme? : @theme.Theme = @theme.default(),
) -> Bool {
  guard self.find(reference) is Some(input) else { return false }
  if !input.single_line || width <= 0 || width > 1024 {
    return false
  }
  if !@raster.matches_layout(
      input.engine,
      text,
      width,
      true,
      typography=theme.typography,
    ) {
    ignore(
      @raster.render(
        input.engine,
        text,
        width,
        theme.typography.line_height.ceil().to_int(),
        single_line_scroll=Some(0),
        theme~,
      ),
    )
  }
  if @raster.caret_position(input.engine, text.length()) is Some((end_x, _)) {
    input.scroll_x = input.scroll_x.min((end_x - width + 1).max(0))
  }
  if active_caret is Some(caret) {
    if @raster.caret_position(input.engine, caret) is Some((x, _)) {
      if x < input.scroll_x {
        input.scroll_x = x.max(0)
      } else if x >= input.scroll_x + width {
        input.scroll_x = (x - width + 1).max(0)
      }
    }
  }
  true
}

///|
pub fn Registry::sync_vertical_scroll(
  self : Registry,
  reference : @semantics.NodeRef,
) -> Bool {
  guard self.find(reference) is Some(input) else { return false }
  if input.single_line {
    return false
  }
  input.scroll_y = @raster.vertical_scroll(input.engine)
  true
}

///|
pub fn Registry::scroll_vertical(
  self : Registry,
  reference : @semantics.NodeRef,
  delta : Int,
) -> Bool {
  guard self.find(reference) is Some(input) && !input.single_line else {
    return false
  }
  input.scroll_y = (input.scroll_y.to_int64() + delta.to_int64())
    .max(0L)
    .min(2147483647L)
    .to_int()
  true
}

///|
pub fn Registry::remove(
  self : Registry,
  reference : @semantics.NodeRef,
) -> Unit {
  self.inputs = self.inputs.filter(input => {
    input.reference != reference && self.live(input.reference)
  })
}

///|
pub fn Registry::clear(self : Registry) -> Unit {
  self.inputs.clear()
}
