///|
enum LoadPhase {
  NotLoaded
  Loading
  Ready
  LoadFailed(String)
} derive(Eq, Debug)

///|
priv struct Persistence {
  snapshot : @snapshot.Snapshot
  resource : @resource.Resource
  status_value : @reactive.Signal[String]
  mut phase : LoadPhase
  mut saving : Bool
  mut save_error : String?
  mut edit_error : String?
  mut revision : Int
  mut saved_revision : Int?
  mut close_pending : Bool
  mut close_discarded : Bool
}

///|
fn Persistence::new(
  scope : @reactive.Scope,
  snapshot : @snapshot.Snapshot,
) -> Persistence {
  {
    snapshot,
    resource: @resource.Resource::new(scope),
    status_value: @reactive.Signal::new(scope, "Load pending"),
    phase: NotLoaded,
    saving: false,
    save_error: None,
    edit_error: None,
    revision: 0,
    saved_revision: Some(0),
    close_pending: false,
    close_discarded: false,
  }
}

///|
fn Persistence::connect(
  self : Persistence,
  control : @task.TaskControl,
) -> Unit {
  if !self.resource.connect(control) {
    abort("Work-order storage task connection failed")
  }
}

///|
fn Persistence::dirty(self : Persistence) -> Bool {
  self.saved_revision != Some(self.revision)
}

///|
fn Persistence::status(self : Persistence) -> String {
  self.status_value.get()
}

///|
fn Persistence::refresh(self : Persistence) -> Unit {
  let state = match self.phase {
    NotLoaded => "Load pending"
    Loading => "Loading..."
    LoadFailed(message) => "Load failed: " + message
    Ready =>
      if self.edit_error is Some(message) {
        "Edit rejected: " + message
      } else if self.saving {
        "Saving..."
      } else if self.save_error is Some(message) {
        "Save failed: " + message
      } else if self.dirty() {
        "Unsaved changes"
      } else {
        "Saved"
      }
  }
  self.status_value.set(
    if self.close_pending {
      "Close requested | " + state
    } else {
      state
    },
  )
}

///|
fn snapshot_failure(error : @snapshot.Failure) -> String {
  match error {
    TooLarge => "Snapshot exceeds 1 MiB"
    AccessDenied => "Storage access denied"
    CapacityExceeded => "Storage capacity exceeded"
    Busy => "Storage is busy"
    Closed => "Storage is closed"
    InvalidData => "Stored data is invalid"
    Failed => "Storage operation failed"
  }
}

///|
fn Persistence::can_edit(self : Persistence) -> Bool {
  self.phase == Ready && !self.close_pending
}

///|
fn Persistence::can_save(self : Persistence) -> Bool {
  self.phase == Ready &&
  !self.saving &&
  (self.dirty() || self.save_error is Some(_))
}

///|
fn Persistence::can_retry_load(self : Persistence) -> Bool {
  self.phase is NotLoaded || self.phase is LoadFailed(_)
}

///|
fn Persistence::load(
  self : Persistence,
  on_loaded : (Array[WorkOrder]) -> Unit,
) -> @task.Request? {
  guard self.can_retry_load() else { return None }
  self.resource.replace(
    () => {
      self.phase = Loading
      self.refresh()
    },
    () => self.snapshot.load(),
    result => {
      match result {
        Ok(None) => {
          self.phase = Ready
          self.revision = 1
          self.saved_revision = None
          on_loaded(seed_orders())
        }
        Ok(Some(text)) =>
          match decode_orders(text) {
            Ok(orders) => {
              self.phase = Ready
              self.revision = 0
              self.saved_revision = Some(0)
              on_loaded(orders)
            }
            Err(message) => self.phase = LoadFailed(message)
          }
        Err(error) => self.phase = LoadFailed(snapshot_failure(error))
      }
      self.refresh()
      @task.Changed
    },
    on_failure=message => {
      self.phase = LoadFailed(message)
      self.refresh()
      @task.Changed
    },
  )
}

///|
fn Persistence::edited(self : Persistence) -> Unit {
  if self.revision == 0x7fffffff {
    abort("Work-order revision exhausted")
  }
  self.revision += 1
  self.edit_error = None
  self.refresh()
}

///|
fn Persistence::reject_edit(self : Persistence, message : String) -> Unit {
  self.edit_error = Some(message)
  self.refresh()
}

///|
fn Persistence::save(
  self : Persistence,
  orders : Array[WorkOrder],
) -> @task.Request? {
  guard self.can_save() else { return None }
  let text = encode_orders(orders)
  let revision = self.revision
  self.resource.replace(
    () => {
      self.saving = true
      self.save_error = None
      self.edit_error = None
      self.refresh()
    },
    () => self.snapshot.save(text),
    result => {
      self.saving = false
      match result {
        Ok(_) => {
          self.saved_revision = Some(revision)
          self.save_error = None
        }
        Err(error) => self.save_error = Some(snapshot_failure(error))
      }
      self.refresh()
      @task.Changed
    },
    on_failure=message => {
      self.saving = false
      self.save_error = Some(message)
      self.refresh()
      @task.Changed
    },
  )
}

///|
fn Persistence::request_close(self : Persistence) -> Unit {
  self.close_pending = true
  self.close_discarded = false
  self.refresh()
}

///|
fn Persistence::discard_and_close(self : Persistence) -> Unit {
  if self.close_pending && !self.saving {
    self.close_discarded = true
    self.refresh()
  }
}

///|
fn Persistence::cancel_close(self : Persistence) -> Unit {
  self.close_pending = false
  self.close_discarded = false
  self.refresh()
}

///|
fn Persistence::can_close(self : Persistence) -> Bool {
  !self.saving &&
  self.phase != Loading &&
  (self.close_discarded || !self.dirty())
}

///|
fn Persistence::close_ready(self : Persistence) -> Bool {
  self.close_pending && self.can_close()
}
