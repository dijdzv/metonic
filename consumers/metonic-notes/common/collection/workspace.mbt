///|
pub struct Workspace {
  priv mut document : Document
  priv mut saved : Document
  priv mut selected : Int?
  priv mut delete_candidate : Int?
}

///|
pub fn workspace(document : Document) -> Workspace {
  {
    document,
    saved: document,
    selected: document.items().get(0).map(note => note.id),
    delete_candidate: None,
  }
}

///|
pub fn Workspace::items(self : Workspace) -> Array[Note] {
  self.document.items()
}

///|
pub fn Workspace::active(self : Workspace) -> Note? {
  match self.selected {
    Some(id) => self.document.find(id)
    None => None
  }
}

///|
pub fn Workspace::dirty(self : Workspace) -> Bool {
  self.document != self.saved
}

///|
pub fn Workspace::select(self : Workspace, id : Int) -> Bool {
  guard self.document.find(id) is Some(_) else { return false }
  self.selected = Some(id)
  self.delete_candidate = None
  true
}

///|
pub fn Workspace::reorder_selected(
  self : Workspace,
  direction : MoveDirection,
) -> Bool {
  self.delete_candidate = None
  guard self.selected is Some(id) else { return false }
  match self.document.reorder(id, direction) {
    Err(_) => false
    Ok(document) =>
      if document == self.document {
        false
      } else {
        self.document = document
        true
      }
  }
}

///|
pub fn Workspace::create_note(self : Workspace) -> Result[Int, String] {
  match self.document.create_note() {
    Err(error) => Err(error)
    Ok((document, id)) => {
      self.document = document
      self.selected = Some(id)
      self.delete_candidate = None
      Ok(id)
    }
  }
}

///|
pub fn Workspace::edit(self : Workspace, text : String) -> Result[Unit, String] {
  guard self.selected is Some(id) else { return Err("Select or create a memo") }
  match self.document.edit(id, text) {
    Err(error) => Err(error)
    Ok(document) => {
      self.document = document
      self.delete_candidate = None
      Ok(())
    }
  }
}

///|
pub fn Workspace::request_delete(self : Workspace) -> Bool {
  self.delete_candidate = self.selected
  self.delete_candidate is Some(_)
}

///|
pub fn Workspace::deletion_pending(self : Workspace) -> Bool {
  self.delete_candidate is Some(_)
}

///|
pub fn Workspace::confirm_delete(self : Workspace) -> Bool {
  guard self.delete_candidate is Some(id) && self.selected == Some(id) else {
    return false
  }
  guard self.document.remove(id) is Ok(document) else { return false }
  self.document = document
  self.selected = document.items().get(0).map(note => note.id)
  self.delete_candidate = None
  true
}

///|
pub fn Workspace::snapshot(self : Workspace) -> Document {
  self.document
}

///|
pub fn Workspace::acknowledge_save(
  self : Workspace,
  snapshot : Document,
) -> Unit {
  self.saved = snapshot
}

///|
pub fn Workspace::discard(self : Workspace) -> Unit {
  self.document = self.saved
  if self.active() is None {
    self.selected = self.document.items().get(0).map(note => note.id)
  }
  self.delete_candidate = None
}
