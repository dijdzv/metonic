///|
priv struct PresentationRuntime {
  persistence : @persistence.State
  close_pending : Bool
  save_waiting : Bool
  filtered : Bool
} derive(Eq)

///|
fn PresentationRuntime::ready(self : PresentationRuntime) -> Bool {
  match self.persistence {
    Ready | Saving | SaveFailed(_) => true
    _ => false
  }
}

///|
priv struct ActionPresentation {
  name : String
  enabled : Bool
} derive(Eq)

///|
fn action_presentation(
  workspace : @collection.WorkspaceState,
  runtime : PresentationRuntime,
) -> Array[ActionPresentation] {
  let ready = runtime.ready()
  let saving = runtime.persistence == @persistence.Saving
  let active = workspace.active()
  let ordered = workspace.items()
  let mut move_up = false
  let mut move_down = false
  if !runtime.filtered && active is Some(selected) {
    for index, note in ordered {
      if note.id == selected.id {
        move_up = index > 0
        move_down = index + 1 < ordered.length()
        break
      }
    }
  }
  if runtime.close_pending {
    return [
      { name: "Save", enabled: ready, },
      { name: "Discard", enabled: ready && (!saving || runtime.save_waiting), },
      { name: "Cancel", enabled: true, },
      {
        name: if workspace.deletion_pending() {
          "Confirm delete"
        } else {
          "Delete memo"
        },
        enabled: false,
      },
      { name: "Move up", enabled: false, },
      { name: "Move down", enabled: false, },
    ]
  }
  [
    {
      name: if runtime.persistence is @persistence.LoadFailed(_) {
        "Retry load"
      } else {
        "Save all"
      },
      enabled: runtime.persistence is @persistence.LoadFailed(_) || ready,
    },
    {
      name: "Discard all changes",
      enabled: ready && (!saving || runtime.save_waiting),
    },
    { name: "New memo", enabled: ready, },
    {
      name: if workspace.deletion_pending() {
        "Confirm delete"
      } else {
        "Delete memo"
      },
      enabled: ready && active is Some(_),
    },
    { name: "Move up", enabled: ready && move_up, },
    { name: "Move down", enabled: ready && move_down, },
  ]
}
