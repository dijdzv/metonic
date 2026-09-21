///|
pub struct Driver {
  priv commands : @aqueue.Queue[(Int, @task.Request)]
  priv mut accepting : Bool
  priv mut started : Bool
  priv mut generation : Int
}

///|
pub fn driver() -> Driver {
  {
    commands: @aqueue.Queue(kind=@aqueue.Blocking(16)),
    accepting: true,
    started: false,
    generation: 0,
  }
}

///|
pub fn Driver::submit(self : Driver, request : @task.Request) -> Bool {
  guard self.accepting else { return false }
  let generation = self.generation + 1
  let accepted = self.commands.try_put((generation, request)) catch {
    _ => false
  }
  if accepted {
    self.generation = generation
  }
  accepted
}

///|
pub fn Driver::close(self : Driver) -> Unit {
  guard self.accepting else { return }
  self.accepting = false
  self.commands.close(clear=true)
}

///|
pub async fn Driver::run(
  self : Driver,
  post : (@task.Completion) -> Unit,
) -> Unit {
  guard !self.started else { return }
  self.started = true
  defer self.close()
  @async.with_task_group(group => {
    let mut previous : @async.Task[Unit]? = None
    while self.accepting {
      let command = Some(self.commands.get()) catch {
        @aqueue.QueueAlreadyClosed => None
        other => raise other
      }
      guard command is Some((generation, request)) else { break }
      guard self.accepting else { break }
      previous = dispatch(request, previous, group, completion => {
        if self.accepting && self.generation == generation {
          // Delivery can precede a later UI event; acceptance must be checked
          // again when the host applies the result, not only when it is queued.
          post(
            @task.completion(() => {
              if self.accepting && self.generation == generation {
                completion.apply()
              } else {
                @task.Rejected
              }
            }),
          )
        }
      })
    }
    cancel_and_wait(previous)
  })
}
