///|
pub(all) struct Control {
  reference : @semantics.NodeRef
  bounds : @view.Bounds
  toggled : Bool?
}

///|
pub(all) struct Status {
  id : UInt64
  text : String
  bounds : @view.Bounds
}

///|
pub(all) struct Presentation {
  title : String
  width : Int
  height : Int
  controls : Array[Control]
  statuses : Array[Status]
  text_owner : @semantics.NodeRef?
  composing : Bool
  text_scroll : Int
}

///|
fn Presentation::snapshot(self : Presentation) -> Presentation {
  { ..self, controls: self.controls.copy(), statuses: self.statuses.copy(), }
}

///|
fn Presentation::control(
  self : Presentation,
  reference : @semantics.NodeRef,
) -> Control? {
  for item in self.controls {
    if item.reference == reference {
      return Some(item)
    }
  }
  None
}

///|
fn owner_node(
  nodes : Array[@semantics.Node],
  owner : @semantics.NodeRef?,
) -> @semantics.Node? {
  for node in nodes {
    if owner == Some(node.reference) {
      return Some(node)
    }
  }
  None
}

///|
fn valid_bounds(bounds : @view.Bounds) -> Bool {
  bounds.width >= 0 && bounds.height >= 0
}

///|
fn valid_presentation(
  nodes : Array[@semantics.Node],
  presentation : Presentation,
) -> Bool {
  if presentation.width < 1 ||
    presentation.height < 1 ||
    presentation.controls.length() != nodes.length() ||
    presentation.text_scroll < 0 {
    return false
  }
  let ids : Array[Int] = []
  for node in nodes {
    if node.reference.id <= 0 || ids.contains(node.reference.id) {
      return false
    }
    ids.push(node.reference.id)
    guard presentation.control(node.reference) is Some(control) else {
      return false
    }
    if !valid_bounds(control.bounds) ||
      (
        control.toggled is Some(_) &&
        node.role != @semantics.Button &&
        node.role != @semantics.Checkbox
      ) {
      return false
    }
  }
  if presentation.text_owner is Some(_) {
    guard owner_node(nodes, presentation.text_owner) is Some(node) &&
      node.role == @semantics.TextInput else {
      return false
    }
  }
  let status_ids : Array[UInt64] = []
  for status in presentation.statuses {
    // Semantic IDs occupy positive Int; text-fragment IDs start at 2^32.
    if status.id < 2147483648UL ||
      status.id >= 4294967296UL ||
      status_ids.contains(status.id) ||
      !valid_bounds(status.bounds) {
      return false
    }
    status_ids.push(status.id)
  }
  true
}
