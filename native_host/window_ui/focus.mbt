///|
fn move_focus(model : @application.Model, reverse : Bool) -> Unit {
  let nodes = @semantics.snapshot(model.editor)
  guard nodes.length() >= 2 else { return }
  let order = [nodes[1], nodes[0]]
  for i = 2; i < nodes.length(); i = i + 1 {
    order.push(nodes[i])
  }
  let mut current = -1
  for i = 0; i < order.length(); i = i + 1 {
    if order[i].focused {
      current = i
      break
    }
  }
  let target = if current < 0 {
    if reverse {
      order.length() - 1
    } else {
      0
    }
  } else if reverse {
    (current + order.length() - 1) % order.length()
  } else {
    (current + 1) % order.length()
  }
  ignore(@semantics.focus(model.editor, order[target].reference))
}
