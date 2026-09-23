///|
fn Collection::save(self : Collection, delay : Int) -> @task.Request? {
  if self.scope.is_disposed() {
    return None
  }
  if delay > 0 && self.persistence.state() is @persistence.SaveFailed(_) {
    return None
  }
  let snapshot = self.workspace.peek().snapshot()
  self.save_resource.replace_prepared(() => (), () => {
    if self.scope.is_disposed() {
      return None
    }
    self.persistence.retire_save()
    self.save_waiting.set(false)
    if self.persistence.saved_text() is Some(saved) &&
      @collection.decode(Some(saved)) is Ok(document) {
      self.workspace.set(self.workspace.peek().acknowledge_save(document))
    }
    if delay > 0 && self.persistence.state() is @persistence.SaveFailed(_) {
      return None
    }
    guard self.ready() && (!self.close_pending.peek() || delay == 0) else {
      return None
    }
    ignore(self.persistence.edit(snapshot.encode()))
    self.save_waiting.set(delay > 0)
    self.persistence.save_work(
      self.store,
      () => {
        self.save_waiting.set(false)
        if self.persistence.is_saved(snapshot.encode()) {
          self.workspace.set(self.workspace.peek().acknowledge_save(snapshot))
        }
      },
      before_save=post_progress => {
        if delay > 0 {
          (self.wait)(delay)
        }
        if self.scope.is_disposed() {
          return false
        }
        let should_save = !self.close_pending.peek() || delay == 0
        if should_save && delay > 0 {
          post_progress(
            @task.completion(() => {
              if self.scope.is_disposed() ||
                self.persistence.state() != @persistence.Saving ||
                !self.save_waiting.peek() {
                @task.Rejected
              } else {
                self.save_waiting.set(false)
                @task.Changed
              }
            }),
          )
        }
        should_save
      },
    )
  })
}
