///|
pub(all) enum Role {
  Label
  Button
  TextInput
} derive(Debug, Eq)

///|
pub(all) struct NodeRef {
  session : Int
  window : Int
  id : Int
  generation : Int
} derive(Debug, Eq)

///|
pub struct Node {
  reference : NodeRef
  role : Role
  name : String
  value : String
  enabled : Bool
  read_only : Bool
  focused : Bool
  selection_start : Int
  selection_end : Int
  selection_anchor : Int
} derive(Debug)

///|
pub struct Tree {
  session : Int
  window : Int
  mut next_id : Int
  mut nodes : Array[Node]
  mut next_generation : Int
  mut closed : Bool
  mut revision : Int
}

///|
pub(all) struct InitialNode {
  role : Role
  name : String
  value : String
}

///|
pub fn create(
  session : Int,
  window : Int,
  initial : Array[InitialNode],
) -> Tree? {
  let tree = empty(session, window)
  for item in initial {
    if @text_position.utf16_to_scalar(item.value, 0) is None {
      return None
    }
    if add_node(tree, item.name, item.role, item.value) is None {
      return None
    }
  }
  tree.revision = 0
  Some(tree)
}

///|
pub fn snapshot(tree : Tree) -> Array[Node] {
  if tree.closed {
    []
  } else {
    tree.nodes.copy()
  }
}

///|
pub fn revision(tree : Tree) -> Int {
  tree.revision
}

///|
fn resolve(tree : Tree, reference : NodeRef) -> (Int, String) {
  if tree.closed {
    return (-1, "closed")
  }
  if reference.session != tree.session || reference.window != tree.window {
    return (-1, "stale_target")
  }
  for node in tree.nodes {
    if node.reference == reference {
      return (reference.id, "")
    }
  }
  (-1, "stale_target")
}

///|
pub fn node(tree : Tree, reference : NodeRef) -> Result[Node, String] {
  let (id, error) = resolve(tree, reference)
  if id < 0 {
    Err(error)
  } else {
    Ok(extra_node(tree, id).unwrap())
  }
}

///|
pub fn set_name(tree : Tree, reference : NodeRef, name : String) -> String {
  let (id, error) = resolve(tree, reference)
  if id < 0 {
    return error
  }
  let node = extra_node(tree, id).unwrap()
  if node.name == name {
    return ""
  }
  store_input(tree, { ..node, name, })
  tree.revision += 1
  ""
}

///|
pub fn set_button_value(
  tree : Tree,
  reference : NodeRef,
  value : String,
) -> String {
  let (id, error) = resolve(tree, reference)
  if id < 0 {
    return error
  }
  let node = extra_node(tree, id).unwrap()
  if node.role != Button {
    return "unsupported_action"
  }
  if !node.enabled {
    return "disabled"
  }
  if node.value == value {
    return ""
  }
  store_input(tree, { ..node, value, })
  tree.revision += 1
  ""
}

///|
pub fn focus(tree : Tree, reference : NodeRef) -> String {
  let (id, error) = resolve(tree, reference)
  if id < 0 {
    return error
  }
  let node = extra_node(tree, id).unwrap()
  if node.role == Label {
    return "unsupported_action"
  }
  if !node.enabled {
    return "disabled"
  }
  if node.focused {
    return ""
  }
  tree.nodes = tree.nodes.map(other => {
    ..other,
    focused: other.reference == reference,
  })
  tree.revision += 1
  ""
}

///|
pub fn set_text(tree : Tree, reference : NodeRef, value : String) -> String {
  set_text_value(tree, reference, value, false)
}

///|
pub fn set_controlled_text(
  tree : Tree,
  reference : NodeRef,
  value : String,
) -> String {
  set_text_value(tree, reference, value, true)
}

///|
fn set_text_value(
  tree : Tree,
  reference : NodeRef,
  value : String,
  controlled : Bool,
) -> String {
  let (kind, error) = resolve(tree, reference)
  if kind < 0 {
    error
  } else if input_node(tree, kind) is None {
    "unsupported_action"
  } else {
    match input_node(tree, kind) {
      Some(node) =>
        if !controlled && !node.enabled {
          "disabled"
        } else if !controlled && node.read_only {
          "read_only"
        } else if @text_position.utf16_to_scalar(value, 0) is None {
          "invalid_text"
        } else if node.value == value {
          ""
        } else {
          let length = value.length()
          store_input(tree, {
            ..node,
            value,
            selection_start: length,
            selection_end: length,
            selection_anchor: length,
          })
          tree.revision += 1
          ""
        }
      None => "stale_target"
    }
  }
}

///|
pub fn replace_selection(
  tree : Tree,
  reference : NodeRef,
  inserted : String,
) -> String {
  let (kind, error) = resolve(tree, reference)
  if kind < 0 {
    return error
  }
  if input_node(tree, kind) is None {
    return "unsupported_action"
  }
  match input_node(tree, kind) {
    None => "stale_target"
    Some(node) => {
      if !node.enabled {
        return "disabled"
      }
      if node.read_only {
        return "read_only"
      }
      if @text_position.utf16_to_scalar(inserted, 0) is None {
        return "invalid_text"
      }
      let start = node.selection_start
      let end = node.selection_end
      let value = node.value[:start].to_owned() +
        inserted +
        node.value[end:].to_owned()
      let insertion_end = start + inserted.length()
      let caret = if selection_boundary(value, insertion_end) {
        insertion_end
      } else {
        insertion_end + 1
      }
      if value != node.value || start != caret || end != caret {
        store_input(tree, {
          ..node,
          value,
          selection_start: caret,
          selection_end: caret,
          selection_anchor: caret,
        })
        tree.revision += 1
      }
      ""
    }
  }
}

///|
pub fn delete_backward(tree : Tree, reference : NodeRef) -> String {
  let (kind, error) = resolve(tree, reference)
  if kind < 0 {
    return error
  }
  if input_node(tree, kind) is None {
    return "unsupported_action"
  }
  let node = input_node(tree, kind).unwrap()
  if !node.enabled {
    return "disabled"
  }
  if node.read_only {
    return "read_only"
  }
  if node.selection_start != node.selection_end {
    return replace_selection(tree, reference, "")
  }
  if node.selection_start == 0 {
    return ""
  }
  let mut start = node.selection_start - 1
  while !selection_boundary(node.value, start) {
    start -= 1
  }
  let value = node.value[:start].to_owned() +
    node.value[node.selection_end:].to_owned()
  let caret = if selection_boundary(value, start) { start } else { start + 1 }
  store_input(tree, {
    ..node,
    value,
    selection_start: caret,
    selection_end: caret,
    selection_anchor: caret,
  })
  tree.revision += 1
  ""
}

///|
pub fn delete_forward(tree : Tree, reference : NodeRef) -> String {
  let (kind, error) = resolve(tree, reference)
  if kind < 0 {
    return error
  }
  guard input_node(tree, kind) is Some(node) else {
    return "unsupported_action"
  }
  if !node.enabled {
    return "disabled"
  }
  if node.read_only {
    return "read_only"
  }
  if node.selection_start != node.selection_end {
    return replace_selection(tree, reference, "")
  }
  let start = node.selection_start
  if start == node.value.length() {
    return ""
  }
  let mut end = start + 1
  while !selection_boundary(node.value, end) {
    end += 1
  }
  let value = node.value[:start].to_owned() + node.value[end:].to_owned()
  let caret = if selection_boundary(value, start) { start } else { start + 1 }
  store_input(tree, {
    ..node,
    value,
    selection_start: caret,
    selection_end: caret,
    selection_anchor: caret,
  })
  tree.revision += 1
  ""
}

///|
fn selection_boundary(value : String, index : Int) -> Bool {
  // Splitting CRLF would expose a caret position that native text ranges cannot represent.
  @text_position.utf16_to_scalar(value, index) is Some(_) &&
  !(index > 0 &&
  index < value.length() &&
  value[index - 1].to_int() == 13 &&
  value[index].to_int() == 10)
}

///|
pub fn set_enabled(tree : Tree, reference : NodeRef, enabled : Bool) -> String {
  let (id, error) = resolve(tree, reference)
  if id < 0 {
    return error
  }
  let node = extra_node(tree, id).unwrap()
  if node.enabled == enabled {
    return ""
  }
  store_input(tree, { ..node, enabled, focused: enabled && node.focused, })
  tree.revision += 1
  ""
}

///|
pub fn set_read_only(
  tree : Tree,
  reference : NodeRef,
  read_only : Bool,
) -> String {
  let (id, error) = resolve(tree, reference)
  if id < 0 {
    return error
  }
  guard input_node(tree, id) is Some(node) else { return "unsupported_action" }
  if node.read_only == read_only {
    return ""
  }
  store_input(tree, { ..node, read_only, })
  tree.revision += 1
  ""
}

///|
pub fn set_selection(
  tree : Tree,
  reference : NodeRef,
  start : Int,
  end : Int,
) -> String {
  if start > end {
    return "invalid_selection"
  }
  set_selection_directed(tree, reference, start, end)
}

///|
pub fn set_selection_directed(
  tree : Tree,
  reference : NodeRef,
  anchor : Int,
  caret : Int,
) -> String {
  let start = anchor.min(caret)
  let end = anchor.max(caret)
  let (kind, error) = resolve(tree, reference)
  if kind < 0 {
    error
  } else if input_node(tree, kind) is None {
    "unsupported_action"
  } else {
    match input_node(tree, kind) {
      Some(node) => {
        let length = node.value.length()
        if !node.enabled {
          "disabled"
        } else if start < 0 ||
          start > end ||
          end > length ||
          !selection_boundary(node.value, start) ||
          !selection_boundary(node.value, end) {
          "invalid_selection"
        } else if node.selection_start == start &&
          node.selection_end == end &&
          node.selection_anchor == anchor {
          ""
        } else {
          store_input(tree, {
            ..node,
            selection_start: start,
            selection_end: end,
            selection_anchor: anchor,
          })
          tree.revision += 1
          ""
        }
      }
      None => "stale_target"
    }
  }
}

///|
pub fn remove(tree : Tree, reference : NodeRef) -> String {
  let (id, error) = resolve(tree, reference)
  if id < 0 {
    return error
  }
  tree.nodes = tree.nodes.filter(node => node.reference != reference)
  tree.revision += 1
  ""
}

///|
pub fn restore_input(
  tree : Tree,
  id : Int,
  name : String,
  value : String,
) -> NodeRef? {
  if tree.closed ||
    id < 1 ||
    id >= tree.next_id ||
    extra_node(tree, id) is Some(_) ||
    @text_position.utf16_to_scalar(value, 0) is None ||
    tree.next_generation == 2147483647 {
    return None
  }
  let reference = NodeRef::{
    session: tree.session,
    window: tree.window,
    id,
    generation: tree.next_generation,
  }
  tree.next_generation += 1
  tree.nodes.push({
    reference,
    role: TextInput,
    name,
    value,
    enabled: true,
    read_only: false,
    focused: false,
    selection_start: value.length(),
    selection_end: value.length(),
    selection_anchor: value.length(),
  })
  tree.nodes.sort_by((a, b) => a.reference.id.compare(b.reference.id))
  tree.revision += 1
  Some(reference)
}

///|
pub fn dispose(tree : Tree) -> Bool {
  if tree.closed {
    return false
  }
  tree.nodes = []
  tree.closed = true
  tree.revision += 1
  true
}

///|
fn extra_node(tree : Tree, id : Int) -> Node? {
  for node in tree.nodes {
    if node.reference.id == id {
      return Some(node)
    }
  }
  None
}

///|
pub fn add_button(tree : Tree, name : String) -> NodeRef? {
  add_node(tree, name, Button, "")
}

///|
pub fn add_label(tree : Tree, text : String) -> NodeRef? {
  add_node(tree, text, Label, "")
}

///|
fn add_node(
  tree : Tree,
  name : String,
  role : Role,
  value : String,
) -> NodeRef? {
  if tree.closed ||
    tree.next_id == 2147483647 ||
    tree.next_generation == 2147483647 {
    return None
  }
  let reference = {
    session: tree.session,
    window: tree.window,
    id: tree.next_id,
    generation: tree.next_generation,
  }
  tree.next_id += 1
  tree.next_generation += 1
  tree.nodes.push({
    reference,
    role,
    name,
    value,
    enabled: true,
    read_only: false,
    focused: false,
    selection_start: value.length(),
    selection_end: value.length(),
    selection_anchor: value.length(),
  })
  tree.revision += 1
  Some(reference)
}
