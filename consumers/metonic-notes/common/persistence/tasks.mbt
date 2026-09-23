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
          if self.finish_load(ticket, result) {
            changed()
            @task.Changed
          } else {
            @task.Rejected
          }
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
              defer (if !completed.val && self.cancel_save(ticket) {
                changed()
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
              if self.finish_save(ticket, result) {
                changed()
                @task.Changed
              } else {
                @task.Rejected
              }
            },
          ),
        )
      },
      operation~,
    ),
  )
}
