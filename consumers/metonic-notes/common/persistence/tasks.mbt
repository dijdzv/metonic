///|
pub(all) struct Store {
  load : async () -> Result[String?, String]
  save : async (String) -> Result[Unit, String]
}

///|
pub fn Model::load_request(
  self : Model,
  store : Store,
  changed : () -> Unit,
) -> @task.Request? {
  guard self.begin_load() is Some(ticket) else { return None }
  Some(
    @task.replace(() => (), () => {
      Some(
        @task.work(() => (store.load)(), result => {
          let outcome = Ref(@task.Outcome::Rejected)
          (self.batch)(() => {
            if self.finish_load(ticket, result) {
              changed()
              outcome.val = @task.Changed
            }
          })
          outcome.val
        }),
      )
    }),
  )
}

///|
pub fn Model::save_request(
  self : Model,
  store : Store,
  changed : () -> Unit,
  operation : @task.Operation,
  before_save? : async ((@task.Completion) -> Unit) -> Bool = _ => true,
) -> @task.Request? {
  guard self.save_work(store, changed, before_save~) is Some(work) else {
    return None
  }
  Some(@task.replace(() => (), () => Some(work), operation~))
}

///|
pub fn Model::save_work(
  self : Model,
  store : Store,
  changed : () -> Unit,
  before_save? : async ((@task.Completion) -> Unit) -> Bool = _ => true,
) -> @task.Work? {
  guard self.begin_save() is Some((ticket, snapshot)) else { return None }
  Some(
    @task.work_with_progress(
      post_progress => {
        if !before_save(post_progress) {
          return None
        }
        let result = (store.save)(snapshot)
        self.record_save(ticket, snapshot, result)
        Some(result)
      },
      result => {
        match result {
          Some(result) => {
            let outcome = Ref(@task.Outcome::Rejected)
            (self.batch)(() => {
              if self.finish_save(ticket, result) {
                changed()
                outcome.val = @task.Changed
              }
            })
            outcome.val
          }
          None => {
            let outcome = Ref(@task.Outcome::Unchanged)
            (self.batch)(() => {
              if self.cancel_save(ticket) {
                changed()
                outcome.val = @task.Changed
              }
            })
            outcome.val
          }
        }
      },
    ),
  )
}
