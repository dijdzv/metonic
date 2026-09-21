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
}

///|
pub(all) struct TextEdit {
  target : @semantics.NodeRef
  text : String
  revision : Int
}

///|
pub(all) struct Application {
  title : String
  editor : @semantics.Tree
  default_input : @semantics.NodeRef?
  initial_size : (Int, Int)
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
