///|
pub struct Cycle {
  priv id : Int
} derive(Debug, Eq, Hash)

///|
let next_cycle : Ref[Int] = Ref(0)

///|
let next_source_id : Ref[Int] = Ref(0)

///|
let next_admission_id : Ref[Int] = Ref(0)

///|
let next_state_revision : Ref[Int] = Ref(0)

///|
fn fresh_identity(counter : Ref[Int], name : String) -> Int {
  guard counter.val < 0x7fffffff else { abort(name + " identity exhausted") }
  counter.val += 1
  counter.val
}

///|
pub fn Cycle::new() -> Cycle {
  { id: fresh_identity(next_cycle, "async cycle"), }
}

///|
pub(all) struct Snapshot[K, V] {
  key : K
  cycle : Cycle
  value : V
} derive(Debug, Eq)

///|
pub(all) enum AsyncState[K, V] {
  Idle
  Pending(K, Cycle, Snapshot[K, V]?)
  Ready(K, Cycle, V, Snapshot[K, V]?)
  Failed(K, Cycle, String, Snapshot[K, V]?)
  Canceled(K, Cycle, Snapshot[K, V]?)
} derive(Debug, Eq)

///|
pub struct Source[K, V] {
  priv scope : @reactive.Scope
  priv resource : Resource
  priv state : @reactive.Signal[AsyncState[K, V]]
  priv source_id : Int
  priv admission_id : Ref[Int]
  priv state_revision : Ref[Int]
  priv mut trace : ((TraceKind) -> Unit)?
}

///|
pub fn[K, V] Source::new(parent : @reactive.Scope) -> Source[K, V] {
  let state : @reactive.Signal[AsyncState[K, V]] = @reactive.Signal::new_by(
    parent,
    Idle,
    fn(_, _) { false },
  )
  {
    scope: parent,
    resource: Resource::new(parent),
    state,
    source_id: fresh_identity(next_source_id, "source"),
    admission_id: Ref(0),
    state_revision: Ref(0),
    trace: None,
  }
}

///|
pub fn[K, V] Source::connect(
  self : Source[K, V],
  control : @task.TaskControl,
) -> Bool {
  self.resource.connect(control)
}

///|
pub fn[K, V] Source::get(self : Source[K, V]) -> AsyncState[K, V] {
  self.state.get()
}

///|
pub fn[K, V] Source::peek(self : Source[K, V]) -> AsyncState[K, V] {
  self.state.peek()
}

///|
fn[K, V] Source::publish(
  self : Source[K, V],
  next : AsyncState[K, V],
  failed_kind? : TraceKind = FailedTransition,
) -> Unit {
  self.state_revision.val = fresh_identity(next_state_revision, "source state")
  self.state.set(next)
  if self.trace is Some(record) {
    record(
      match next {
        Idle => PendingTransition
        Pending(_, _, _) => PendingTransition
        Ready(_, _, _, _) => ReadyTransition
        Failed(_, _, _, _) => failed_kind
        Canceled(_, _, _) => CanceledTransition
      },
    )
  }
}

///|
fn[K, V] Source::record_trace(self : Source[K, V], kind : TraceKind) -> Unit {
  if self.trace is Some(record) {
    record(kind)
  }
}

///|
fn[K : Eq, V] previous_for(
  state : AsyncState[K, V],
  key : K,
) -> Snapshot[K, V]? {
  match state {
    Ready(current, cycle, value, _) if current == key =>
      Some({ key, cycle, value, })
    Pending(current, _, previous)
    | Failed(current, _, _, previous)
    | Canceled(current, _, previous)
    | Ready(current, _, _, previous) if current == key => previous
    _ => None
  }
}

///|
fn[K : Eq, V] Source::proposal(
  self : Source[K, V],
  key : K,
  cycle : Cycle,
  retain_previous : Bool,
  prepare : (Snapshot[K, V]?) -> @task.Work?,
) -> @task.Request? {
  let retained : Ref[Snapshot[K, V]?] = Ref(None)
  self.resource.replace_prepared(
    () => {
      retained.val = if retain_previous {
        previous_for(self.state.peek(), key)
      } else {
        None
      }
      self.admission_id.val = fresh_identity(next_admission_id, "admission")
      self.publish(Pending(key, cycle, retained.val))
    },
    () => prepare(retained.val),
    on_failure=message => {
      self.publish(
        Failed(key, cycle, message, retained.val),
        failed_kind=UnexpectedFailure,
      )
      @task.Failed(message)
    },
  )
}

///|
pub fn[K : Eq, V] Source::replace_with_progress(
  self : Source[K, V],
  key : K,
  cycle : Cycle,
  retain_previous : Bool,
  run : async ((@task.Completion) -> Unit) -> V,
) -> @task.Request? {
  self.proposal(key, cycle, retain_previous, previous => {
    Some(
      @task.work_with_progress(run, value => {
        self.publish(Ready(key, cycle, value, previous))
        @task.Changed
      }),
    )
  })
}

///|
pub fn[K : Eq, V] Source::replace(
  self : Source[K, V],
  key : K,
  cycle : Cycle,
  retain_previous : Bool,
  run : async () -> V,
) -> @task.Request? {
  self.replace_with_progress(key, cycle, retain_previous, _ => run())
}

///|
pub fn[K : Eq, V, E] Source::replace_result(
  self : Source[K, V],
  key : K,
  cycle : Cycle,
  retain_previous : Bool,
  run : async () -> Result[V, E],
  error_text : (E) -> String,
) -> @task.Request? {
  self.proposal(key, cycle, retain_previous, previous => {
    Some(
      @task.work(run, result => {
        match result {
          Ok(value) => self.publish(Ready(key, cycle, value, previous))
          Err(error) =>
            self.publish(
              Failed(key, cycle, error_text(error), previous),
              failed_kind=ExpectedFailure,
            )
        }
        @task.Changed
      }),
    )
  })
}

///|
pub fn[K, V] Source::cancel(self : Source[K, V]) -> @task.Request? {
  self.resource.cancel(() => {
    match self.state.peek() {
      Pending(key, cycle, previous) => {
        self.record_trace(CancellationRequested)
        self.publish(Canceled(key, cycle, previous))
      }
      _ => ()
    }
  })
}

///|
/// Stops an obsolete in-flight value immediately, even when the Driver cannot
/// accept another Request. It does not claim that cleanup has finished.
pub fn[K, V] Source::retire_current(self : Source[K, V]) -> Bool {
  guard self.resource.retire_current() else { return false }
  match self.state.peek() {
    Pending(key, cycle, previous) => {
      self.record_trace(CancellationRequested)
      self.publish(Canceled(key, cycle, previous))
    }
    _ => ()
  }
  true
}

///|
pub fn[K, V] Source::dispose(self : Source[K, V]) -> Unit {
  guard !self.scope.is_disposed() && !self.resource.is_disposed() else {
    return
  }
  match self.state.peek() {
    Pending(key, cycle, previous) => {
      self.record_trace(CancellationRequested)
      self.publish(Canceled(key, cycle, previous))
    }
    _ => ()
  }
  self.resource.dispose()
}
