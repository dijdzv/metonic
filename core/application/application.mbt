///|
pub(all) enum Kind {
  Text
  Button
  Input(single_line~ : Bool)
} derive(Eq)

///|
pub(all) struct Control {
  element : @view.Element
  kind : Kind
  clip : @view.Bounds?
}

///|
pub fn Control::visible_bounds(self : Control) -> @view.Bounds? {
  match self.clip {
    Some(clip) => self.element.bounds.intersection(clip)
    None => Some(self.element.bounds)
  }
}

///|
pub(all) struct TextEdit {
  target : @semantics.NodeRef
  text : String
  revision : Int
}

///|
pub(all) struct Viewport {
  scroll : (Int, Int, Int) -> Bool
  reveal : (@semantics.NodeRef) -> Bool
}

///|
pub(all) struct Application {
  title : String
  editor : @semantics.Tree
  default_input : @semantics.NodeRef?
  initial_size : (Int, Int)
  viewport : Viewport?
  connect_tasks : (@task.TaskControl) -> Unit
  initialize : () -> @task.Request?
  view : () -> Array[Control]
  activate : (@semantics.NodeRef) -> @task.Request?
  edited : (TextEdit) -> @task.Request?
  resize : (Int, Int) -> Bool
  stop : () -> Unit
  can_close : () -> Bool
  close_requested : () -> Unit
  close_ready : () -> Bool
  input_error : (String?) -> Unit
  dispose : async () -> Unit
}
