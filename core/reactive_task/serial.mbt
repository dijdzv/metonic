///|
/// One immutable write value and the caller's deduplication identity. Register
/// one SerialTask per independent serialization lane, such as one document.
pub(all) struct SerialJob[I, T] {
  identity : I
  value : T
}

///|
pub(all) enum SerialCompletion[I, T, V] {
  Succeeded(SerialJob[I, T], V)
  Failed(SerialJob[I, T], String)
}

///|
pub(all) struct SerialSnapshot[I, T, V] {
  active : SerialJob[I, T]?
  queued : Array[SerialJob[I, T]]
  last : SerialCompletion[I, T, V]?
  admission_rejected : Bool
}

///|
priv struct SerialEntry {
  owner : @reactive.Scope
  connect : (@task.TaskControl) -> Bool
  offer : ((@task.Request) -> Bool) -> Bool
  mut active : Bool
}

///|
pub struct SerialRegistry {
  priv root : @reactive.Scope
  priv entries : Array[SerialEntry]
  priv mut control : @task.TaskControl?
  priv mut reconciling : Bool
}

///|
pub struct SerialTask[I, T, V] {
  priv owner : @reactive.Scope
  priv resource : Resource
  priv queue : Array[SerialJob[I, T]]
  priv completed : @hashset.HashSet[I]
  priv mut active : SerialJob[I, T]?
  priv mut last : SerialCompletion[I, T, V]?
  priv mut attempted : Bool
  priv mut rejected : Bool
  priv state : @reactive.Signal[SerialSnapshot[I, T, V]]
  priv run : async (T) -> Result[V, String]
  priv on_applied : (SerialJob[I, T], Result[V, String]) -> Unit
}

///|
pub fn SerialRegistry::new(root : @reactive.Scope) -> SerialRegistry {
  if root.is_disposed() {
    abort("serial registry requires a live root scope")
  }
  { root, entries: [], control: None, reconciling: false, }
}

///|
pub fn SerialRegistry::connect(
  self : SerialRegistry,
  control : @task.TaskControl,
) -> Bool {
  guard !self.root.is_disposed() && self.control is None else { return false }
  self.control = Some(control)
  for entry in self.entries {
    if entry.active && !entry.owner.is_disposed() && !(entry.connect)(control) {
      abort("serial Resource could not connect to the application Driver")
    }
  }
  true
}

///|
pub fn[I : Eq + Hash, T, V] SerialRegistry::register(
  self : SerialRegistry,
  owner : @reactive.Scope,
  run : async (T) -> Result[V, String],
  on_applied : (SerialJob[I, T], Result[V, String]) -> Unit,
) -> SerialTask[I, T, V] {
  if self.reconciling ||
    self.root.is_disposed() ||
    owner.is_disposed() ||
    !self.root.contains(owner) {
    abort("serial registration requires a live owner below its registry")
  }
  let resource = Resource::new(owner)
  if self.control is Some(control) && !resource.connect(control) {
    abort("serial Resource could not connect to the application Driver")
  }
  let state = @reactive.Signal::new_by(
    owner,
    SerialSnapshot::{
      active: None,
      queued: [],
      last: None,
      admission_rejected: false,
    },
    fn(_, _) { false },
  )
  let writer : SerialTask[I, T, V] = {
    owner,
    resource,
    queue: [],
    completed: @hashset.HashSet([]),
    active: None,
    last: None,
    attempted: false,
    rejected: false,
    state,
    run,
    on_applied,
  }
  let entry : SerialEntry = {
    owner,
    connect: task_control => resource.connect(task_control),
    offer: submit => writer.offer(submit),
    active: true,
  }
  self.entries.push(entry)
  owner.on_dispose(() => {
    entry.active = false
    self.entries.retain(candidate => !physical_equal(candidate, entry))
    writer.queue.clear()
    writer.active = None
  })
  writer
}

///|
fn[I, T, V] SerialTask::publish(self : SerialTask[I, T, V]) -> Unit {
  self.state.set({
    active: self.active,
    queued: self.queue.copy(),
    last: self.last,
    admission_rejected: self.rejected,
  })
}

///|
pub fn[I, T, V] SerialTask::snapshot(
  self : SerialTask[I, T, V],
) -> SerialSnapshot[I, T, V] {
  let state = self.state.get()
  { ..state, queued: state.queued.copy(), }
}

///|
pub fn[I : Eq + Hash, T, V] SerialTask::enqueue(
  self : SerialTask[I, T, V],
  identity : I,
  value : T,
) -> Bool {
  guard !self.owner.is_disposed() else { return false }
  if self.completed.contains(identity) ||
    (self.active is Some(active) && active.identity == identity) ||
    self.queue.any(job => job.identity == identity) {
    return false
  }
  self.queue.push({ identity, value, })
  self.publish()
  true
}

///|
pub fn[I, T, V] SerialTask::retry(self : SerialTask[I, T, V]) -> Bool {
  guard !self.owner.is_disposed() &&
    self.active is None &&
    !self.queue.is_empty() &&
    self.rejected else {
    return false
  }
  self.attempted = false
  self.rejected = false
  self.publish()
  true
}

///|
pub fn[I, T, V] SerialTask::cancel(self : SerialTask[I, T, V]) -> Bool {
  guard !self.owner.is_disposed() else { return false }
  let changed = self.active is Some(_) || !self.queue.is_empty()
  self.queue.clear()
  self.active = None
  self.attempted = false
  self.rejected = false
  if changed {
    ignore(self.resource.retire_current())
    self.publish()
  }
  changed
}

///|
fn[I : Eq + Hash, T, V] SerialTask::finish(
  self : SerialTask[I, T, V],
  job : SerialJob[I, T],
  result : Result[V, String],
) -> @task.Outcome {
  guard !self.owner.is_disposed() else { return @task.Rejected }
  self.active = None
  self.attempted = false
  self.rejected = false
  self.last = Some(
    match result {
      Ok(value) => Succeeded(job, value)
      Err(error) => Failed(job, error)
    },
  )
  if result is Ok(_) {
    self.completed.add(job.identity)
  }
  (self.on_applied)(job, result)
  if !self.owner.is_disposed() {
    self.publish()
  }
  @task.Changed
}

///|
fn[I : Eq + Hash, T, V] SerialTask::offer(
  self : SerialTask[I, T, V],
  submit : (@task.Request) -> Bool,
) -> Bool {
  guard !self.owner.is_disposed() &&
    self.active is None &&
    !self.queue.is_empty() &&
    !self.attempted else {
    return false
  }
  let job = self.queue[0]
  let request = self.resource.replace(
    () => {
      ignore(self.queue.remove(0))
      self.active = Some(job)
      self.attempted = true
      self.rejected = false
      self.publish()
    },
    () => (self.run)(job.value),
    result => self.finish(job, result),
    on_failure=message => self.finish(job, Err(message)),
  )
  guard request is Some(request) else { return false }
  if !submit(request) {
    self.attempted = true
    self.rejected = true
    self.publish()
  }
  true
}

///|
pub fn SerialRegistry::reconcile(
  self : SerialRegistry,
  submit : (@task.Request) -> Bool,
) -> Bool {
  guard !self.root.is_disposed() && self.control is Some(_) else {
    return false
  }
  if self.reconciling {
    abort("serial reconciliation cannot re-enter")
  }
  self.reconciling = true
  defer {
    self.reconciling = false
  }
  let mut changed = false
  for entry in self.entries.copy() {
    if entry.active && !entry.owner.is_disposed() && (entry.offer)(submit) {
      changed = true
    }
  }
  changed
}
