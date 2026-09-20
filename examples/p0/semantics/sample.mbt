///|
pub using @editing {
  type Tree,
  type Node,
  type NodeRef,
  type Role,
  type Composition,
  snapshot,
  revision,
  focus,
  set_text,
  replace_selection,
  delete_backward,
  delete_forward,
  set_enabled,
  set_selection,
  set_selection_directed,
  remove,
  dispose,
  add_button,
  add_input,
  navigate,
  caret,
}

///|
pub fn create(session : Int, window : Int) -> Tree {
  @editing.create(session, window, [
    { role: Button, name: "Toggle", value: "off", },
    { role: TextInput, name: "Text", value: "", },
  ]).unwrap()
}

///|
pub fn activate(tree : Tree, reference : NodeRef) -> String {
  let node = match @editing.node(tree, reference) {
    Ok(node) => node
    Err(error) => return error
  }
  if reference.id != 1 || node.role != Button {
    return "unsupported_action"
  }
  @editing.set_button_value(
    tree,
    reference,
    if node.value == "off" {
      "on"
    } else {
      "off"
    },
  )
}

///|
pub fn recreate_input(tree : Tree) -> NodeRef? {
  @editing.restore_input(tree, 2, "Text", "")
}

///|
pub fn begin_composition(tree : Tree, target? : NodeRef) -> Composition? {
  let reference = match target {
    Some(reference) => reference
    None => {
      for node in snapshot(tree) {
        if node.reference.id == 2 {
          return @editing.begin_composition(tree, target=node.reference)
        }
      }
      return None
    }
  }
  @editing.begin_composition(tree, target=reference)
}
