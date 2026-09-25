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
  publications : @reactive_task.PublicationRegistry?
  downstreams : @reactive_task.DownstreamRegistry?
  serials : @reactive_task.SerialRegistry?
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

///|
pub fn Application::publish(self : Application) -> Bool {
  self.publications.map(registry => registry.publish()).unwrap_or(false)
}

///|
pub fn Application::reconcile_downstreams(
  self : Application,
  submit : (@task.Request) -> Bool,
) -> Bool {
  self.downstreams.map(registry => registry.reconcile(submit)).unwrap_or(false)
}

///|
pub fn Application::reconcile_tasks(
  self : Application,
  submit : (@task.Request) -> Bool,
) -> Bool {
  let downstream = self.reconcile_downstreams(submit)
  let serial = self.serials
    .map(registry => registry.reconcile(submit))
    .unwrap_or(false)
  downstream || serial
}
