///|
fn Collection::save(self : Collection, delay : Int) -> @task.Request? {
  if self.scope.is_disposed() {
    return None
  }
  if delay > 0 && self.persistence.state() is @persistence.SaveFailed(_) {
    return None
  }
  let snapshot = self.workspace.peek().snapshot()
  Some(
    @task.replace(
      () => (),
      () => {
        if self.scope.is_disposed() {
          return None
        }
        self.persistence.retire_save()
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
        let request = self.persistence.save_request(
          self.store,
          () => {
            self.save_waiting.set(false)
            if self.persistence.is_saved(snapshot.encode()) {
              self.workspace.set(
                self.workspace.peek().acknowledge_save(snapshot),
              )
            }
          },
          self.save_operation,
          before_save=() => {
            if delay > 0 {
              (self.wait)(delay)
            }
            if self.scope.is_disposed() {
              return false
            }
            self.save_waiting.set(false)
            !self.close_pending.peek() || delay == 0
          },
        )
        request.bind(request => request.prepare())
      },
      operation=self.save_operation,
    ),
  )
}
