///|
fn App::report_edit(
  self : App,
  target : @semantics.NodeRef,
  previous : String,
) -> Unit {
  guard !self.closed else { return }
  guard (self.host.view)().inputs.any(input => input.reference == target) else {
    return
  }
  guard @semantics.node(self.host.editor, target) is Ok(node) &&
    node.enabled &&
    node.value != previous else {
    return
  }
  if (self.host.edited)({
      target,
      text: node.value,
      revision: @semantics.revision(self.host.editor),
    })
    is Some(action) {
    self.queue(ApplicationTask(action.request, action.gate, () => ()))
  }
}

///|
fn App::finish_edit(self : App, accepted : Bool) -> Unit {
  let original = self.composition_original
  self.composition_original = None
  if accepted && original is Some((target, previous)) {
    self.report_edit(target, previous)
  }
}
