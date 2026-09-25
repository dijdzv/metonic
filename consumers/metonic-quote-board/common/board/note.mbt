///|
pub(all) struct SaveSnapshot {
  document : String
  text : String
  revision : Int
}

///|
priv struct NoteState {
  document : String
  mut text : String
  mut edit_revision : Int
  mut saved_revision : Int
  mut error : String?
  mut closing : Bool
}

///|
priv struct Note {
  state : NoteState
  input : @component.UiInput
  save_button : @semantics.NodeRef
  writer : @async_state.SerialTask[Int, SaveSnapshot, Unit]
}

///|
fn Note::new(
  scope : @reactive.Scope,
  tree : @semantics.Tree,
  ui : @component.UiRoot,
  registry : @async_state.SerialRegistry,
  save : async (SaveSnapshot) -> Result[Unit, String],
) -> Note {
  let state : NoteState = {
    document: "quote-board-note",
    text: "",
    edit_revision: 0,
    saved_revision: 0,
    error: None,
    closing: false,
  }
  let writer = registry.register(scope, save, (job, result) => {
    match result {
      Ok(_) => {
        if job.identity > state.saved_revision {
          state.saved_revision = job.identity
        }
        state.error = None
      }
      Err(message) => state.error = Some(message)
    }
  })
  {
    state,
    input: ui
    .fixed("note")
    .text_area(
      "body",
      "Note",
      @component.Controlled::new(() => state.text, text => {
        state.edit(text)
        None
      }),
    )
    .unwrap(),
    save_button: @semantics.add_button(tree, "Save note").unwrap(),
    writer,
  }
}

///|
fn NoteState::edit(self : NoteState, text : String) -> Unit {
  if self.text != text {
    self.text = text
    self.edit_revision += 1
    self.error = None
  }
}

///|
fn Note::save(self : Note) -> Bool {
  let state = self.state
  let retried = if self.writer.snapshot().admission_rejected {
    self.writer.retry()
  } else {
    false
  }
  guard state.edit_revision > state.saved_revision else { return retried }
  let submitted = self.writer.enqueue(state.edit_revision, {
    document: state.document,
    text: state.text,
    revision: state.edit_revision,
  })
  if submitted {
    state.error = None
  }
  retried || submitted
}

///|
fn Note::can_close(self : Note) -> Bool {
  let snapshot = self.writer.snapshot()
  self.state.edit_revision == self.state.saved_revision &&
  snapshot.active is None &&
  snapshot.queued.is_empty()
}

///|
fn Note::request_close(self : Note) -> Unit {
  self.state.closing = true
  ignore(self.save())
}

///|
fn Note::close_ready(self : Note) -> Bool {
  self.state.closing && self.can_close()
}

///|
fn Note::status(self : Note) -> String {
  let snapshot = self.writer.snapshot()
  let prefix = if self.state.closing { "Closing · " } else { "" }
  if snapshot.admission_rejected {
    return prefix + "Note: save not admitted; press Save note to retry"
  }
  if snapshot.active is Some(active) {
    let saved = if self.state.saved_revision > 0 {
      "saved revision " + self.state.saved_revision.to_string() + "; "
    } else {
      ""
    }
    if self.state.edit_revision > active.identity {
      return prefix +
        "Note: " +
        saved +
        "saving revision " +
        active.identity.to_string() +
        "; newer edit " +
        self.state.edit_revision.to_string() +
        " is unsaved"
    }
    return prefix +
      "Note: " +
      saved +
      "saving revision " +
      active.identity.to_string()
  }
  if !snapshot.queued.is_empty() {
    return prefix + "Note: queued for save"
  }
  if self.state.error is Some(message) {
    return prefix + "Note: save failed: " + message
  }
  if self.state.edit_revision > self.state.saved_revision {
    return prefix +
      "Note: unsaved revision " +
      self.state.edit_revision.to_string()
  }
  if self.state.saved_revision > 0 {
    return prefix +
      "Note: saved revision " +
      self.state.saved_revision.to_string()
  }
  prefix + "Note: no edits"
}
