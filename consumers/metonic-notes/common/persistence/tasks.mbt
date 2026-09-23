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
  before_save? : async () -> Bool = () => true,
) -> @task.Request? {
  guard self.begin_save() is Some((ticket, snapshot)) else { return None }
  Some(
    @task.replace(
      () => (),
      () => {
        Some(
          @task.work(
            () => {
              let completed = Ref(false)
              defer (self.batch)(() => {
                if !completed.val && self.cancel_save(ticket) {
                  changed()
                }
              })
              if !before_save() {
                return None
              }
              let result = (store.save)(snapshot)
              self.record_save(ticket, result)
              completed.val = true
              Some(result)
            },
            result => {
              guard result is Some(result) else { return @task.Unchanged }
              let outcome = Ref(@task.Outcome::Rejected)
              (self.batch)(() => {
                if self.finish_save(ticket, result) {
                  changed()
                  outcome.val = @task.Changed
                }
              })
              outcome.val
            },
          ),
        )
      },
      operation~,
    ),
  )
}
