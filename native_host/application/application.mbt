///|
pub(all) struct View {
  items : Array[@renderer.Item]
  inputs : Array[@view_presentation.Input]
  rectangle : @gpu.SurfaceRectangle?
  accessibility : @accessibility.Presentation
}

///|
pub(all) enum TaskGate {
  Always
  PointerIdle
  CommittedInput
}

///|
pub(all) struct TaskAction {
  request : @task.Request
  gate : TaskGate
}

///|
pub(all) struct Application {
  editor : @semantics.Tree
  default_input : @semantics.NodeRef?
  initialize : () -> TaskAction?
  initial_size : (Int, Int)
  view : () -> View
  focus_order : () -> Array[@semantics.NodeRef]
  activate : (@semantics.NodeRef) -> TaskAction?
  activate_unhandled : () -> Bool
  shortcut : (@core.Key, Bool, Bool) -> TaskAction?
  navigate_unhandled : (Int, Int) -> Bool
  navigation_blocked : () -> Bool
  pointer_unhandled : (Int, Int) -> Bool
  resize : (Int, Int) -> Bool
  stop : () -> Unit
  can_close : () -> Bool
  close_requested : () -> Unit
  close_ready : () -> Bool
  input_error : (String?) -> Unit
  dispose : async () -> Unit
}

///|
pub fn move_focus(
  editor : @semantics.Tree,
  order : Array[@semantics.NodeRef],
  reverse : Bool,
) -> Unit {
  let available = order.filter(reference => {
    match @semantics.node(editor, reference) {
      Ok(node) => node.enabled
      Err(_) => false
    }
  })
  if available.is_empty() {
    return
  }
  let mut current = -1
  for index, reference in available {
    if @semantics.node(editor, reference).unwrap().focused {
      current = index
      break
    }
  }
  let target = if current < 0 {
    if reverse {
      available.length() - 1
    } else {
      0
    }
  } else if reverse {
    (current + available.length() - 1) % available.length()
  } else {
    (current + 1) % available.length()
  }
  ignore(@semantics.focus(editor, available[target]))
}
