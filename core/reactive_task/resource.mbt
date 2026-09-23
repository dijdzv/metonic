///|
pub struct Resource {
  priv scope : @reactive.Scope
  priv operation : @task.Operation
  priv mut control : @task.TaskControl?
  priv mut generation : Int
}

///|
pub fn Resource::new(parent : @reactive.Scope) -> Resource {
  let scope = parent.child()
  let resource : Resource = {
    scope,
    operation: @task.Operation::new(),
    control: None,
    generation: 0,
  }
  scope.on_dispose(() => {
    resource.generation += 1
    if resource.control is Some(control) {
      control.cancel(resource.operation)
    }
  })
  resource
}

///|
pub fn Resource::connect(self : Resource, control : @task.TaskControl) -> Bool {
  if self.scope.is_disposed() || self.control is Some(_) {
    return false
  }
  self.control = Some(control)
  true
}

///|
pub fn Resource::is_disposed(self : Resource) -> Bool {
  self.scope.is_disposed()
}

///|
pub fn Resource::dispose(self : Resource) -> Unit {
  self.scope.dispose()
}

///|
pub fn Resource::replace_prepared(
  self : Resource,
  invalidate : () -> Unit,
  prepare : () -> @task.Work?,
  on_failure? : (String) -> @task.Outcome = message => @task.Failed(message),
) -> @task.Request? {
  guard !self.scope.is_disposed() && self.control is Some(_) else {
    return None
  }
  let ticket : Ref[Int?] = Ref(None)
  Some(
    @task.replace(
      () => {
        if !self.scope.is_disposed() {
          self.generation += 1
          ticket.val = Some(self.generation)
          invalidate()
        }
      },
      () => {
        guard ticket.val is Some(generation) &&
          !self.scope.is_disposed() &&
          self.generation == generation else {
          return None
        }
        guard prepare() is Some(work) else { return None }
        Some(
          @task.work_with_progress(
            post_progress => {
              work.run(post_progress=progress => {
                post_progress(
                  @task.completion(() => {
                    if self.scope.is_disposed() || self.generation != generation {
                      @task.Rejected
                    } else {
                      progress.apply()
                    }
                  }),
                )
              })
            },
            completion => {
              if self.scope.is_disposed() || self.generation != generation {
                @task.Rejected
              } else {
                completion.apply()
              }
            },
          ),
        )
      },
      operation=self.operation,
      on_failure=message => {
        guard ticket.val is Some(generation) &&
          !self.scope.is_disposed() &&
          self.generation == generation else {
          return @task.Rejected
        }
        on_failure(message)
      },
    ),
  )
}

///|
pub fn[T] Resource::replace(
  self : Resource,
  invalidate : () -> Unit,
  run : async () -> T,
  apply : (T) -> @task.Outcome,
  on_failure? : (String) -> @task.Outcome = message => @task.Failed(message),
) -> @task.Request? {
  self.replace_prepared(
    invalidate,
    () => Some(@task.work(run, apply)),
    on_failure~,
  )
}

///|
pub fn Resource::cancel(
  self : Resource,
  invalidate : () -> Unit,
) -> @task.Request? {
  guard !self.scope.is_disposed() && self.control is Some(_) else {
    return None
  }
  Some(
    @task.cancel(
      () => {
        if !self.scope.is_disposed() {
          self.generation += 1
          invalidate()
        }
      },
      operation=self.operation,
    ),
  )
}
