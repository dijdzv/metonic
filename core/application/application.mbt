///|
pub(all) enum Kind {
  Text
  Button
  Checkbox
  List
  ListItem
  Status
  Input(single_line~ : Bool)
} derive(Eq)

///|
pub(all) struct Control {
  element : @view.Element
  kind : Kind
  clip : @view.Bounds?
}

///|
pub fn button(
  widget : @component.UiButton,
  bounds : @view.Bounds,
  clip? : @view.Bounds? = None,
) -> Control {
  { element: widget.element(bounds), kind: Button, clip, }
}

///|
pub fn checkbox(
  widget : @component.UiCheckbox,
  bounds : @view.Bounds,
  clip? : @view.Bounds? = None,
) -> Control {
  { element: widget.element(bounds), kind: Checkbox, clip, }
}

///|
pub fn[K] list(
  widget : @component.UiList[K],
  bounds : @view.Bounds,
  clip? : @view.Bounds? = None,
) -> Control {
  { element: widget.element(bounds), kind: List, clip, }
}

///|
pub fn[K] list_item(
  widget : @component.UiListItem[K],
  bounds : @view.Bounds,
  clip? : @view.Bounds? = None,
) -> Control {
  { element: widget.element(bounds), kind: ListItem, clip, }
}

///|
pub fn status(
  widget : @component.UiStatus,
  bounds : @view.Bounds,
  clip? : @view.Bounds? = None,
) -> Control {
  { element: widget.element(bounds), kind: Status, clip, }
}

///|
pub fn label(
  widget : @component.UiLabel,
  bounds : @view.Bounds,
  clip? : @view.Bounds? = None,
) -> Control {
  { element: widget.element(bounds), kind: Text, clip, }
}

///|
pub fn input(
  widget : @component.UiInput,
  bounds : @view.Bounds,
  clip? : @view.Bounds? = None,
) -> Control {
  {
    element: widget.element(bounds),
    kind: Input(single_line=widget.single_line()),
    clip,
  }
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
  components : @component.UiRoot?
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
pub fn Application::synchronize_components(
  self : Application,
  composing : @semantics.NodeRef?,
) -> Bool {
  self.components.map(root => root.synchronize(composing)).unwrap_or(false)
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
