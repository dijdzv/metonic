///|
pub(all) enum StatusState {
  Waiting(String)
  Loading(String)
  RetainedPrevious(String, String)
  Rejected(String)
  Failed(String)
  Canceled(String)
  Ready(String)
} derive(Eq)

///|
pub fn StatusState::message(self : StatusState) -> String {
  let text = match self {
    Waiting(message)
    | Loading(message)
    | Rejected(message)
    | Failed(message)
    | Canceled(message)
    | Ready(message) => message
    RetainedPrevious(message, value) => message + " (previous " + value + ")"
  }
  if text.length() <= 160 {
    text
  } else {
    match self {
      RetainedPrevious(_, _) => "Previous result available"
      Rejected(_) | Failed(_) => "Operation failed"
      Loading(_) => "Loading"
      Waiting(_) => "Waiting"
      Canceled(_) => "Canceled"
      Ready(_) => "Result available"
    }
  }
}

///|
pub fn StatusState::is_error(self : StatusState) -> Bool {
  self is Rejected(_) || self is Failed(_)
}

///|
priv struct UiStatusBinding {
  key : String
  owner : ChildOwner
  reference : @semantics.NodeRef
  value : PreparedInput[StatusState]
}

///|
pub struct UiStatus {
  priv root : UiRoot
  priv owner : ChildOwner
  priv reference : @semantics.NodeRef
}

///|
pub fn UiOwner::status(
  self : UiOwner,
  key : String,
  value : Read[StatusState],
) -> UiStatus? {
  self.check_key(key)
  let prepared_value = PreparedInput::new(self.child.scope(), value)
  let initial = prepared_value.current()
  guard self.child.add_status(initial.message()) is Some(reference) else {
    return None
  }
  if initial.is_error() {
    ignore(@semantics.set_invalid(self.root.tree, reference, true))
  }
  prepared_value.consume()
  self.root.statuses.push({
    key,
    owner: self.child,
    reference,
    value: prepared_value,
  })
  self.child
  .scope()
  .on_dispose(() => {
    self.root.statuses.retain(status => status.reference != reference)
  })
  Some({ root: self.root, owner: self.child, reference, })
}

///|
pub fn UiStatus::reference(self : UiStatus) -> @semantics.NodeRef {
  self.reference
}

///|
pub fn UiStatus::element(
  self : UiStatus,
  bounds : @view.Bounds,
) -> @view.Element {
  if !self.owner.owns(self.reference) {
    abort("UI status owner is disposed")
  }
  let node = @semantics.node(self.root.tree, self.reference).unwrap()
  { bounds, text: node.name, reference: Some(self.reference), focused: false, }
}
