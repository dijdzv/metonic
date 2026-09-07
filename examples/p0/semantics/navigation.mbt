///|
pub fn caret(node : Node) -> Int {
  if node.selection_anchor == node.selection_start {
    node.selection_end
  } else {
    node.selection_start
  }
}

///|
pub fn navigate(
  tree : Tree,
  reference : NodeRef,
  forward : Bool,
  extend_selection : Bool,
) -> String {
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
  let position = caret(node)
  let next = if !extend_selection && node.selection_start != node.selection_end {
    if forward {
      node.selection_end
    } else {
      node.selection_start
    }
  } else {
    let step = if forward { 1 } else { -1 }
    let mut offset = (position + step).max(0).min(node.value.length())
    while !selection_boundary(node.value, offset) {
      offset += step
    }
    offset
  }
  let anchor = if extend_selection { node.selection_anchor } else { next }
  set_selection_directed(tree, reference, anchor, next)
}
