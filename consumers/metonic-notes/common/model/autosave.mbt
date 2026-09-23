///|
fn Collection::save(self : Collection, delay : Int) -> @task.Request? {
  if delay > 0 && self.persistence.state() is @persistence.SaveFailed(_) {
    return None
  }
  let snapshot = self.workspace.snapshot()
  Some(
    @task.replace(
      () => (),
      () => {
        self.persistence.retire_save()
        if self.persistence.saved_text() is Some(saved) &&
          @collection.decode(Some(saved)) is Ok(document) {
          self.workspace.acknowledge_save(document)
        }
        if delay > 0 && self.persistence.state() is @persistence.SaveFailed(_) {
          self.sync()
          return None
        }
        guard self.ready() && (!self.close_pending || delay == 0) else {
          self.sync()
          return None
        }
        ignore(self.persistence.edit(snapshot.encode()))
        self.save_waiting = delay > 0
        let request = self.persistence.save_request(
          self.store,
          () => {
            self.save_waiting = false
            if self.persistence.is_saved(snapshot.encode()) {
              self.workspace.acknowledge_save(snapshot)
            }
            self.sync()
          },
          self.save_operation,
          before_save=() => {
            if delay > 0 {
              (self.wait)(delay)
            }
            self.save_waiting = false
            !self.close_pending || delay == 0
          },
        )
        self.sync()
        request.bind(request => request.prepare())
      },
      operation=self.save_operation,
    ),
  )
}
