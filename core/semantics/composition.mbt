///|
pub struct Composition {
  priv tree : Tree
  priv node : Node
  priv mut active : Bool
}

///|
pub fn begin_composition(tree : Tree, target~ : NodeRef) -> Composition? {
  if tree.closed {
    return None
  }
  let (id, _) = resolve(tree, target)
  let node = if id < 0 { None } else { input_node(tree, id) }
  match node {
    Some(node) if node.enabled => Some({ tree, node, active: true, })
    _ => None
  }
}

///|
pub fn Composition::preview(self : Composition, preedit : String) -> String? {
  if !self.active || !self.current() {
    return None
  }
  Some(
    self.node.value[:self.node.selection_start].to_owned() +
    preedit +
    self.node.value[self.node.selection_end:].to_owned(),
  )
}

///|
pub fn Composition::commit(self : Composition, text : String) -> String {
  if !self.active {
    return "composition_ended"
  }
  self.active = false
  if !self.current() {
    return "stale_composition"
  }
  replace_selection(self.tree, self.node.reference, text)
}

///|
pub fn Composition::presentation(
  self : Composition,
  preedit : String,
  cursor : Int,
) -> (String, Int, Int, Int)? {
  guard @text_position.utf16_to_scalar(preedit, cursor) is Some(_) else {
    return None
  }
  guard self.preview(preedit) is Some(text) else { return None }
  let start = self.node.selection_start
  Some((text, start, start + preedit.length(), start + cursor))
}

///|
pub fn Composition::cancel(self : Composition) -> Unit {
  self.active = false
}

///|
pub fn Composition::remove_selected_text(self : Composition) -> Composition? {
  if !self.active || !self.current() {
    return None
  }
  if self.node.selection_start == self.node.selection_end {
    return Some(self)
  }
  guard self.commit("") == "" else { return None }
  begin_composition(self.tree, target=self.node.reference)
}

///|
fn Composition::current(self : Composition) -> Bool {
  guard !self.tree.closed && node(self.tree, self.node.reference) is Ok(current) else {
    return false
  }
  current.enabled &&
  current.value == self.node.value &&
  current.selection_start == self.node.selection_start &&
  current.selection_end == self.node.selection_end &&
  current.selection_anchor == self.node.selection_anchor
}
