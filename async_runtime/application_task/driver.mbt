///|
priv struct Lane {
  operation : @task.Operation
  mut generation : Int
  mut running : @async.Task[Unit]?
}

///|
pub struct Driver {
  priv commands : @aqueue.Queue[(Lane, Int, @task.Request, () -> Unit)]
  priv lanes : Map[@task.Operation, Lane]
  priv mut accepting : Bool
  priv mut started : Bool
  priv mut pending_commands : Int
}

///|
pub fn driver() -> Driver {
  {
    commands: @aqueue.Queue(kind=@aqueue.Blocking(16)),
    lanes: {},
    accepting: true,
    started: false,
    pending_commands: 0,
  }
}

///|
pub fn Driver::submit(
  self : Driver,
  request : @task.Request,
  on_prepared? : () -> Unit = () => (),
) -> Bool {
  guard self.accepting && self.pending_commands < 16 else { return false }
  let operation = request.operation()
  let lane = match self.lanes.get(operation) {
    Some(lane) => lane
    None => {
      guard self.lanes.length() < 16 else { return false }
      Lane::{ operation, generation: 0, running: None, }
    }
  }
  let generation = lane.generation + 1
  let accepted = self.commands.try_put((lane, generation, request, on_prepared)) catch {
    _ => false
  }
  if accepted {
    self.pending_commands += 1
    lane.generation = generation
    self.lanes[operation] = lane
    request.invalidate()
  }
  accepted
}

///|
pub fn Driver::close(self : Driver) -> Unit {
  guard self.accepting else { return }
  self.accepting = false
  while (self.commands.try_get() catch { _ => None })
        is Some((_, _, _, on_prepared)) {
    self.pending_commands -= 1
    on_prepared()
  }
  self.commands.close(clear=true)
  for _, lane in self.lanes {
    if lane.running is Some(running) {
      running.cancel()
    }
  }
}

///|
fn Driver::deliver(
  self : Driver,
  lane : Lane,
  generation : Int,
  completion : @task.Completion,
  post : (@task.Completion) -> Unit,
) -> Unit {
  if self.accepting && lane.generation == generation {
    post(
      @task.completion(() => {
        if self.accepting && lane.generation == generation {
          self.lanes.remove(lane.operation)
          completion.apply()
        } else {
          @task.Rejected
        }
      }),
    )
  }
}

///|
pub async fn Driver::run(
  self : Driver,
  post : (@task.Completion) -> Unit,
  on_state_change? : () -> Unit = () => (),
) -> Unit {
  guard !self.started else { return }
  self.started = true
  defer {
    self.close()
    self.lanes.clear()
  }
  @async.with_task_group(group => {
    while self.accepting {
      let command = Some(self.commands.get()) catch {
        @aqueue.QueueAlreadyClosed => None
        other => raise other
      }
      guard command is Some((lane, generation, request, on_prepared)) else {
        break
      }
      guard self.accepting else {
        self.pending_commands -= 1
        on_prepared()
        break
      }
      let previous = lane.running
      lane.running = Some(
        group.spawn(() => {
          let posted = Ref(false)
          let preparing = Ref(true)
          let acknowledged = Ref(false)
          defer {
            if !acknowledged.val {
              on_prepared()
            }
            if preparing.val {
              self.pending_commands -= 1
            }
            if !posted.val && lane.generation == generation {
              self.lanes.remove(lane.operation)
            }
          }
          cancel_and_wait(previous)
          self.pending_commands -= 1
          preparing.val = false
          guard self.accepting && lane.generation == generation else { return }
          let work = request.prepare()
          on_state_change()
          acknowledged.val = true
          on_prepared()
          guard work is Some(work) else { return }
          let completion = work.run() catch {
            error if cancellation_error(error) => raise error
            error => {
              let message = error.to_string()
              request.failure(message)
            }
          }
          posted.val = true
          self.deliver(lane, generation, completion, post)
        }),
      )
    }
    for _, lane in self.lanes {
      if lane.running is Some(running) {
        running.cancel()
      }
    }
  })
}
