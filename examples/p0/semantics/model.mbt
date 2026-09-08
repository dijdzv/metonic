///|
pub enum Role {
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
  mut extra_buttons : Array[Node]
  mut next_generation : Int
  mut button : Node?
  mut input : Node?
  mut closed : Bool
  mut revision : Int
}

///|
pub fn create(session : Int, window : Int) -> Tree {
  let button_ref = { session, window, id: 1, generation: 1, }
  let input_ref = { session, window, id: 2, generation: 2, }
  {
    session,
    window,
    next_id: 3,
    extra_buttons: [],
    next_generation: 3,
    button: Some({
      reference: button_ref,
      role: Button,
      name: "Toggle",
      value: "off",
      enabled: true,
      focused: false,
      selection_start: 0,
      selection_end: 0,
      selection_anchor: 0,
    }),
    input: Some({
      reference: input_ref,
      role: TextInput,
      name: "Text",
      value: "",
      enabled: true,
      focused: false,
      selection_start: 0,
      selection_end: 0,
      selection_anchor: 0,
    }),
    closed: false,
    revision: 0,
  }
}

///|
pub fn snapshot(tree : Tree) -> Array[Node] {
  if tree.closed {
    []
  } else {
    let nodes = match (tree.button, tree.input) {
      (Some(button), Some(input)) => [button, input]
      (Some(button), None) => [button]
      (None, Some(input)) => [input]
      (None, None) => []
    }
    nodes.append(tree.extra_buttons)
    nodes
  }
}

///|
pub fn revision(tree : Tree) -> Int {
  tree.revision
}

///|
fn resolve(tree : Tree, reference : NodeRef) -> (Int, String) {
  if tree.closed {
    (-1, "closed")
  } else if reference.session != tree.session || reference.window != tree.window {
    (-1, "stale_target")
  } else {
    for node in tree.extra_buttons {
      if node.reference == reference {
        return (node.reference.id, "")
      }
    }
    match (tree.button, tree.input) {
      (Some(node), _) if node.reference == reference => (1, "")
      (_, Some(node)) if node.reference == reference => (2, "")
      (_, _) => (-1, "stale_target")
    }
  }
}

///|
pub fn activate(tree : Tree, reference : NodeRef) -> String {
  let (kind, error) = resolve(tree, reference)
  if kind < 0 {
    error
  } else if kind != 1 {
    "unsupported_action"
  } else {
    match tree.button {
      Some(node) =>
        if !node.enabled {
          "disabled"
        } else {
          tree.button = Some({
            ..node,
            value: if node.value == "off" {
              "on"
            } else {
              "off"
            },
          })
          tree.revision += 1
          ""
        }
      None => "stale_target"
    }
  }
}

///|
pub fn focus(tree : Tree, reference : NodeRef) -> String {
  let (kind, error) = resolve(tree, reference)
  if kind < 0 {
    error
  } else {
    let target = if kind == 1 {
      tree.button
    } else if kind == 2 {
      tree.input
    } else {
      extra_button(tree, kind)
    }
    match target {
      Some(node) =>
        if !node.enabled {
          "disabled"
        } else if node.focused {
          ""
        } else {
          match tree.button {
            Some(other) => tree.button = Some({ ..other, focused: kind == 1, })
            None => ()
          }
          match tree.input {
            Some(other) => tree.input = Some({ ..other, focused: kind == 2, })
            None => ()
          }
          tree.extra_buttons = tree.extra_buttons.map(other => {
            ..other,
            focused: other.reference.id == kind,
          })
          tree.revision += 1
          ""
        }
      None => "stale_target"
    }
  }
}

///|
pub fn set_text(tree : Tree, reference : NodeRef, value : String) -> String {
  let (kind, error) = resolve(tree, reference)
  if kind < 0 {
    error
  } else if kind != 2 {
    "unsupported_action"
  } else {
    match tree.input {
      Some(node) =>
        if !node.enabled {
          "disabled"
        } else if @text_position.utf16_to_scalar(value, 0) is None {
          "invalid_text"
        } else if node.value == value {
          ""
        } else {
          let length = value.length()
          tree.input = Some({
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
  if kind != 2 {
    return "unsupported_action"
  }
  match tree.input {
    None => "stale_target"
    Some(node) => {
      if !node.enabled {
        return "disabled"
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
        tree.input = Some({
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
  if kind != 2 {
    return "unsupported_action"
  }
  let node = tree.input.unwrap()
  if !node.enabled {
    return "disabled"
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
  tree.input = Some({
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
  let (kind, error) = resolve(tree, reference)
  if kind < 0 {
    error
  } else {
    let target = if kind == 1 {
      tree.button
    } else if kind == 2 {
      tree.input
    } else {
      extra_button(tree, kind)
    }
    match target {
      Some(node) =>
        if node.enabled == enabled {
          ""
        } else {
          let updated = {
            ..node,
            enabled,
            focused: if enabled {
              node.focused
            } else {
              false
            },
          }
          if kind == 1 {
            tree.button = Some(updated)
          } else if kind == 2 {
            tree.input = Some(updated)
          } else {
            tree.extra_buttons = tree.extra_buttons.map(other => {
              if other.reference.id == kind {
                updated
              } else {
                other
              }
            })
          }
          tree.revision += 1
          ""
        }
      None => "stale_target"
    }
  }
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
  } else if kind != 2 {
    "unsupported_action"
  } else {
    match tree.input {
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
          tree.input = Some({
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
  let (kind, error) = resolve(tree, reference)
  if kind < 0 {
    error
  } else {
    if kind == 1 {
      tree.button = None
    } else if kind == 2 {
      tree.input = None
    } else {
      tree.extra_buttons = tree.extra_buttons.filter(node => {
        node.reference.id != kind
      })
    }
    tree.revision += 1
    ""
  }
}

///|
pub fn recreate_input(tree : Tree) -> NodeRef? {
  if tree.closed || tree.input is Some(_) || tree.next_generation == 2147483647 {
    None
  } else {
    let reference = {
      session: tree.session,
      window: tree.window,
      id: 2,
      generation: tree.next_generation,
    }
    tree.next_generation += 1
    tree.input = Some({
      reference,
      role: TextInput,
      name: "Text",
      value: "",
      enabled: true,
      focused: false,
      selection_start: 0,
      selection_end: 0,
      selection_anchor: 0,
    })
    tree.revision += 1
    Some(reference)
  }
}

///|
pub fn dispose(tree : Tree) -> Bool {
  if tree.closed {
    false
  } else {
    tree.button = None
    tree.input = None
    tree.extra_buttons = []
    tree.closed = true
    tree.revision += 1
    true
  }
}

///|
fn extra_button(tree : Tree, id : Int) -> Node? {
  for node in tree.extra_buttons {
    if node.reference.id == id {
      return Some(node)
    }
  }
  None
}

///|
pub fn add_button(tree : Tree, name : String) -> NodeRef? {
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
  tree.extra_buttons.push({
    reference,
    role: Button,
    name,
    value: "",
    enabled: true,
    focused: false,
    selection_start: 0,
    selection_end: 0,
    selection_anchor: 0,
  })
  tree.revision += 1
  Some(reference)
}
