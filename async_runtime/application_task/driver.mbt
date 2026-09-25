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
priv struct Command {
  lane : Lane
  generation : Int
  request : @task.Request
}

///|
priv struct CommandGroup {
  commands : Array[Command]
  on_prepared : () -> Unit
}

///|
priv struct PreparedGroup {
  mut remaining : Int
  callback : () -> Unit
}

///|
fn PreparedGroup::ack(self : PreparedGroup) -> Unit {
  guard self.remaining > 0 else { return }
  self.remaining -= 1
  if self.remaining == 0 {
    (self.callback)()
  }
}

///|
pub struct Driver {
  priv commands : @aqueue.Queue[CommandGroup]
  priv lanes : Map[@task.Operation, Lane]
  priv mut accepting : Bool
  priv mut started : Bool
  priv mut pending_commands : Int
  priv mut observer : ((@task.Operation, @task.DriverEvent) -> Unit)?
}

///|
pub fn driver() -> Driver {
  {
    commands: @aqueue.Queue(kind=@aqueue.Blocking(16)),
    lanes: {},
    accepting: true,
    started: false,
    pending_commands: 0,
    observer: None,
  }
}

///|
pub fn Driver::observe(
  self : Driver,
  observer : (@task.Operation, @task.DriverEvent) -> Unit,
) -> Bool {
  guard !self.started && self.observer is None else { return false }
  self.observer = Some(observer)
  true
}

///|
fn Driver::notify(
  self : Driver,
  operation : @task.Operation,
  event : @task.DriverEvent,
) -> Unit {
  if self.observer is Some(observer) {
    observer(operation, event)
  }
}

///|
fn Driver::deny(
  self : Driver,
  members : Array[@task.Request],
  reason : @task.AdmissionDenial,
) -> Bool {
  for item in members {
    if !item.is_group() {
      self.notify(item.operation(), @task.RequestDenied(reason))
    }
  }
  false
}

///|
pub fn Driver::submit(
  self : Driver,
  request : @task.Request,
  on_prepared? : () -> Unit = () => (),
) -> Bool {
  let members = request.members()
  guard self.accepting else { return self.deny(members, @task.DriverClosed) }
  guard !members.is_empty() else { return self.deny(members, @task.EmptyGroup) }
  guard self.pending_commands + members.length() <= 16 else {
    return self.deny(members, @task.PendingCapacity)
  }
  let operations : Array[@task.Operation] = []
  let commands : Array[Command] = []
  let mut new_lanes = 0
  for item in members {
    guard !item.is_group() else { return self.deny(members, @task.NestedGroup) }
    let operation = item.operation()
    guard !operations.contains(operation) else {
      return self.deny(members, @task.DuplicateOperation)
    }
    operations.push(operation)
    let lane = match self.lanes.get(operation) {
      Some(lane) => lane
      None => {
        new_lanes += 1
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
    commands.push({ lane, generation: lane.generation + 1, request: item, })
  }
  guard self.lanes.length() + new_lanes <= 16 else {
    return self.deny(members, @task.LaneCapacity)
  }
  let accepted = self.commands.try_put({ commands, on_prepared, }) catch {
    _ => false
  }
  if accepted {
    self.pending_commands += members.length()
    for command in commands {
      command.lane.generation = command.generation
      command.lane.retiring = false
      self.lanes[command.lane.operation] = command.lane
    }
    request.invalidate()
    for command in commands {
      self.notify(
        command.lane.operation,
        @task.RequestAdmitted(command.generation),
      )
    }
  } else {
    ignore(self.deny(members, @task.QueueFull))
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
  let canceled_generation = lane.generation
  lane.generation += 1
  lane.retiring = true
  self.notify(operation, @task.CancelRequested(canceled_generation))
  if lane.running_active && lane.running is Some(running) {
    running.cancel()
  } else {
    self.remove_current_lane(lane)
    self.notify(operation, @task.CleanupJoined(canceled_generation))
  }
  true
}

///|
pub fn Driver::close(self : Driver) -> Unit {
  guard self.accepting else { return }
  self.accepting = false
  while (self.commands.try_get() catch { _ => None }) is Some(group) {
    self.pending_commands -= group.commands.length()
    for command in group.commands {
      if command.lane.generation == command.generation {
        self.notify(
          command.lane.operation,
          @task.CancelRequested(command.generation),
        )
        self.notify(
          command.lane.operation,
          @task.CleanupJoined(command.generation),
        )
      }
    }
    (group.on_prepared)()
  }
  self.commands.close(clear=true)
  for _, lane in self.lanes {
    if lane.running is Some(running) {
      self.notify(
        lane.operation,
        @task.CancelRequested(lane.running_generation),
      )
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
          self.notify(lane.operation, @task.CompletionDropped(generation))
          @task.Rejected
        }
      }),
    )
  } else {
    self.notify(lane.operation, @task.CompletionDropped(generation))
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
          self.notify(lane.operation, @task.ProgressDropped(generation))
          @task.Rejected
        }
      }),
    )
  } else {
    self.notify(lane.operation, @task.ProgressDropped(generation))
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
      guard command is Some(command_group) else { break }
      guard self.accepting else {
        self.pending_commands -= command_group.commands.length()
        for command in command_group.commands {
          if command.lane.generation == command.generation {
            self.notify(
              command.lane.operation,
              @task.CancelRequested(command.generation),
            )
            self.notify(
              command.lane.operation,
              @task.CleanupJoined(command.generation),
            )
          }
        }
        (command_group.on_prepared)()
        break
      }
      let prepared_group = PreparedGroup::{
        remaining: command_group.commands.length(),
        callback: command_group.on_prepared,
      }
      for command in command_group.commands {
        let lane = command.lane
        let generation = command.generation
        let request = command.request
        let previous = lane.running
        let previous_generation = lane.running_generation
        let previous_active = lane.running_active
        lane.running_generation = generation
        lane.running_active = true
        lane.running = Some(
          group.spawn(() => {
            let posted = Ref(false)
            let preparing = Ref(true)
            let acknowledged = Ref(false)
            defer {
              if !acknowledged.val {
                prepared_group.ack()
              }
              if preparing.val {
                self.pending_commands -= 1
              }
              if lane.running_generation == generation {
                lane.running_active = false
              }
              if (lane.retiring || !self.accepting) &&
                lane.running_generation == generation {
                self.notify(lane.operation, @task.CleanupJoined(generation))
              }
              if (lane.retiring && lane.running_generation == generation) ||
                (!posted.val && lane.generation == generation) {
                self.remove_current_lane(lane)
              }
            }
            if previous_active && previous is Some(_) {
              self.notify(
                lane.operation,
                @task.CancelRequested(previous_generation),
              )
            }
            cancel_and_wait(previous)
            if previous is Some(_) {
              self.notify(
                lane.operation,
                @task.CleanupJoined(previous_generation),
              )
            }
            self.pending_commands -= 1
            preparing.val = false
            guard self.accepting && lane.generation == generation else {
              return
            }
            let work = request.prepare()
            on_state_change()
            acknowledged.val = true
            prepared_group.ack()
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
    }
    for _, lane in self.lanes {
      if lane.running is Some(running) {
        running.cancel()
      }
    }
  })
}
