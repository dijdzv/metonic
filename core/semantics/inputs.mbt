///|
fn input_node(tree : Tree, id : Int) -> Node? {
  let node = extra_node(tree, id)
  match node {
    Some(node) if node.role == TextInput => Some(node)
    _ => None
  }
}

///|
fn store_input(tree : Tree, node : Node) -> Unit {
  tree.nodes = tree.nodes.map(other => {
    if other.reference == node.reference {
      node
    } else {
      other
    }
  })
}

///|
pub fn add_input(tree : Tree, name : String, value : String) -> NodeRef? {
  if @text_position.utf16_to_scalar(value, 0) is None {
    return None
  }
  add_node(tree, name, TextInput, value)
}
