///|
pub struct Composition {
  priv tree : Tree
  priv node : Node
  priv revision : Int
  priv mut active : Bool
}

///|
pub fn begin_composition(tree : Tree, target? : NodeRef) -> Composition? {
  if tree.closed {
    return None
  }
  let node = match target {
    Some(reference) => {
      let (id, _) = resolve(tree, reference)
      if id < 0 {
        None
      } else {
        input_node(tree, id)
      }
    }
    None => tree.input
  }
  match node {
    Some(node) if node.enabled =>
      Some({ tree, node, revision: tree.revision, active: true, })
    _ => None
  }
}

///|
pub fn Composition::preview(self : Composition, preedit : String) -> String? {
  if !self.active || self.tree.closed || self.tree.revision != self.revision {
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
  if self.tree.closed || self.tree.revision != self.revision {
    return "stale_composition"
  }
  replace_selection(self.tree, self.node.reference, text)
}

///|
pub fn Composition::cancel(self : Composition) -> Unit {
  self.active = false
}
