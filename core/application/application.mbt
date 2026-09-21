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
pub(all) struct Application {
  title : String
  editor : @semantics.Tree
  default_input : @semantics.NodeRef
  initial_size : (Int, Int)
  view : () -> Array[Control]
  activate : (@semantics.NodeRef) -> Unit
  resize : (Int, Int) -> Bool
  stop : () -> Unit
}
