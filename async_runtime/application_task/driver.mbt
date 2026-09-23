///|
priv struct Lane {
  operation : @task.Operation
  mut generation : Int
  mut running : @async.Task[Unit]?
  mut running_generation : Int
  mut running_active : Bool
  mut retiring : Bool
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
      Lane::{
        operation,
        generation: 0,
        running: None,
        running_generation: 0,
        running_active: false,
        retiring: false,
      }
    }
  }
  let generation = lane.generation + 1
  let accepted = self.commands.try_put((lane, generation, request, on_prepared)) catch {
    _ => false
  }
  if accepted {
    self.pending_commands += 1
    lane.generation = generation
    lane.retiring = false
    self.lanes[operation] = lane
    request.invalidate()
  }
  accepted
}

///|
fn Driver::remove_current_lane(self : Driver, lane : Lane) -> Unit {
  if self.lanes.get(lane.operation) is Some(current) &&
    physical_equal(current, lane) {
    self.lanes.remove(lane.operation)
  }
}

///|
pub fn Driver::cancel_operation(
  self : Driver,
  operation : @task.Operation,
) -> Bool {
  guard self.accepting && self.lanes.get(operation) is Some(lane) else {
    return false
  }
  lane.generation += 1
  lane.retiring = true
  if lane.running_active && lane.running is Some(running) {
    running.cancel()
  } else {
    self.remove_current_lane(lane)
  }
  true
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
  if self.accepting &&
    lane.generation == generation &&
    self.lanes.get(lane.operation) is Some(current) &&
    physical_equal(current, lane) {
    post(
      @task.completion(() => {
        if self.accepting &&
          lane.generation == generation &&
          self.lanes.get(lane.operation) is Some(current) &&
          physical_equal(current, lane) {
          self.remove_current_lane(lane)
          completion.apply()
        } else {
          @task.Rejected
        }
      }),
    )
  }
}

///|
fn Driver::deliver_progress(
  self : Driver,
  lane : Lane,
  generation : Int,
  progress : @task.Completion,
  post : (@task.Completion) -> Unit,
) -> Unit {
  if self.accepting &&
    lane.generation == generation &&
    self.lanes.get(lane.operation) is Some(current) &&
    physical_equal(current, lane) {
    post(
      @task.completion(() => {
        if self.accepting &&
          lane.generation == generation &&
          self.lanes.get(lane.operation) is Some(current) &&
          physical_equal(current, lane) {
          progress.apply()
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
      lane.running_generation = generation
      lane.running_active = true
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
            if lane.running_generation == generation {
              lane.running_active = false
            }
            if (lane.retiring && lane.running_generation == generation) ||
              (!posted.val && lane.generation == generation) {
              self.remove_current_lane(lane)
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
          let completion = work.run(post_progress=progress => {
            self.deliver_progress(lane, generation, progress, post)
          }) catch {
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
