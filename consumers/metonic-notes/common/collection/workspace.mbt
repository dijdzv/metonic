///|
pub struct WorkspaceState {
  priv document : Document
  priv saved : Document
  priv selected : Int?
  priv delete_candidate : Int?
} derive(Eq, Debug)

///|
pub fn workspace_state(document : Document) -> WorkspaceState {
  {
    document,
    saved: document,
    selected: document.items().get(0).map(note => note.id),
    delete_candidate: None,
  }
}

///|
pub fn WorkspaceState::items(self : WorkspaceState) -> Array[Note] {
  self.document.items()
}

///|
pub fn WorkspaceState::active(self : WorkspaceState) -> Note? {
  match self.selected {
    Some(id) => self.document.find(id)
    None => None
  }
}

///|
pub fn WorkspaceState::dirty(self : WorkspaceState) -> Bool {
  self.document != self.saved
}

///|
pub fn WorkspaceState::select(
  self : WorkspaceState,
  id : Int,
) -> WorkspaceState? {
  guard self.document.find(id) is Some(_) else { return None }
  Some({ ..self, selected: Some(id), delete_candidate: None, })
}

///|
pub fn WorkspaceState::reorder_selected(
  self : WorkspaceState,
  direction : MoveDirection,
) -> (WorkspaceState, Bool) {
  let cleared = { ..self, delete_candidate: None, }
  guard self.selected is Some(id) else { return (cleared, false) }
  match self.document.reorder(id, direction) {
    Err(_) => (cleared, false)
    Ok(document) =>
      if document == self.document {
        (cleared, false)
      } else {
        ({ ..cleared, document, }, true)
      }
  }
}

///|
pub fn WorkspaceState::create_note(
  self : WorkspaceState,
) -> Result[(WorkspaceState, Int), String] {
  match self.document.create_note() {
    Err(error) => Err(error)
    Ok((document, id)) =>
      Ok(
        ({ ..self, document, selected: Some(id), delete_candidate: None, }, id),
      )
  }
}

///|
pub fn WorkspaceState::edit(
  self : WorkspaceState,
  text : String,
) -> Result[WorkspaceState, String] {
  guard self.selected is Some(id) else { return Err("Select or create a memo") }
  match self.document.edit(id, text) {
    Err(error) => Err(error)
    Ok(document) => Ok({ ..self, document, delete_candidate: None, })
  }
}

///|
pub fn WorkspaceState::request_delete(
  self : WorkspaceState,
) -> (WorkspaceState, Bool) {
  ({ ..self, delete_candidate: self.selected, }, self.selected is Some(_))
}

///|
pub fn WorkspaceState::deletion_pending(self : WorkspaceState) -> Bool {
  self.delete_candidate is Some(_)
}

///|
pub fn WorkspaceState::confirm_delete(
  self : WorkspaceState,
) -> (WorkspaceState, Bool) {
  guard self.delete_candidate is Some(id) && self.selected == Some(id) else {
    return (self, false)
  }
  guard self.document.remove(id) is Ok(document) else { return (self, false) }
  (
    {
      ..self,
      document,
      selected: document.items().get(0).map(note => note.id),
      delete_candidate: None,
    },
    true,
  )
}

///|
pub fn WorkspaceState::snapshot(self : WorkspaceState) -> Document {
  self.document
}

///|
pub fn WorkspaceState::acknowledge_save(
  self : WorkspaceState,
  snapshot : Document,
) -> WorkspaceState {
  { ..self, saved: snapshot, }
}

///|
pub fn WorkspaceState::discard(self : WorkspaceState) -> WorkspaceState {
  let restored = { ..self, document: self.saved, delete_candidate: None, }
  if restored.active() is Some(_) {
    restored
  } else {
    {
      ..restored,
      selected: restored.document.items().get(0).map(note => note.id),
    }
  }
}

///|
pub struct Workspace {
  priv mut state : WorkspaceState
}

///|
pub fn workspace(document : Document) -> Workspace {
  { state: workspace_state(document), }
}

///|
pub fn Workspace::items(self : Workspace) -> Array[Note] {
  self.state.items()
}

///|
pub fn Workspace::active(self : Workspace) -> Note? {
  self.state.active()
}

///|
pub fn Workspace::dirty(self : Workspace) -> Bool {
  self.state.dirty()
}

///|
pub fn Workspace::select(self : Workspace, id : Int) -> Bool {
  guard self.state.select(id) is Some(next) else { return false }
  self.state = next
  true
}

///|
pub fn Workspace::reorder_selected(
  self : Workspace,
  direction : MoveDirection,
) -> Bool {
  let (next, changed) = self.state.reorder_selected(direction)
  self.state = next
  changed
}

///|
pub fn Workspace::create_note(self : Workspace) -> Result[Int, String] {
  match self.state.create_note() {
    Err(error) => Err(error)
    Ok((next, id)) => {
      self.state = next
      Ok(id)
    }
  }
}

///|
pub fn Workspace::edit(self : Workspace, text : String) -> Result[Unit, String] {
  match self.state.edit(text) {
    Err(error) => Err(error)
    Ok(next) => {
      self.state = next
      Ok(())
    }
  }
}

///|
pub fn Workspace::request_delete(self : Workspace) -> Bool {
  let (next, requested) = self.state.request_delete()
  self.state = next
  requested
}

///|
pub fn Workspace::deletion_pending(self : Workspace) -> Bool {
  self.state.deletion_pending()
}

///|
pub fn Workspace::confirm_delete(self : Workspace) -> Bool {
  let (next, removed) = self.state.confirm_delete()
  self.state = next
  removed
}

///|
pub fn Workspace::snapshot(self : Workspace) -> Document {
  self.state.snapshot()
}

///|
pub fn Workspace::acknowledge_save(
  self : Workspace,
  snapshot : Document,
) -> Unit {
  self.state = self.state.acknowledge_save(snapshot)
}

///|
pub fn Workspace::discard(self : Workspace) -> Unit {
  self.state = self.state.discard()
}
