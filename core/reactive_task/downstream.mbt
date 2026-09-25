///|
priv struct DownstreamIdentity[K] {
  value : K
  provenance : Provenance
} derive(Eq)

///|
pub(all) enum DownstreamAdmission[K] {
  AwaitingUpstream
  Eligible(K, Provenance)
  Rejected(K, Provenance)
  Admitted(K, Provenance, Cycle)
} derive(Debug, Eq)

///|
priv struct DownstreamControl[K] {
  identity : DownstreamIdentity[K]?
  epoch : Int
  retry : Int
  attempted_epoch : Int
  attempted_retry : Int
  accepted : DownstreamIdentity[K]?
  accepted_cycle : Cycle?
  rejected : Bool
}

///|
priv struct DownstreamEntry {
  owner : @reactive.Scope
  connect : (@task.TaskControl) -> Bool
  prepare : () -> ((@task.Request) -> Bool) -> Bool
  mut active : Bool
}

///|
pub struct DownstreamRegistry {
  priv root : @reactive.Scope
  priv entries : Array[DownstreamEntry]
  priv mut control : @task.TaskControl?
  priv mut reconciling : Bool
}

///|
pub struct Downstream[K, V] {
  priv owner : @reactive.Scope
  priv desired : @reactive.Memo[Current[K]]
  priv source : Source[DownstreamIdentity[K], V]
  priv control : @reactive.Signal[DownstreamControl[K]]
}

///|
pub fn DownstreamRegistry::new(root : @reactive.Scope) -> DownstreamRegistry {
  if root.is_disposed() {
    abort("downstream registry requires a live root scope")
  }
  { root, entries: [], control: None, reconciling: false, }
}

///|
pub fn DownstreamRegistry::connect(
  self : DownstreamRegistry,
  control : @task.TaskControl,
) -> Bool {
  guard !self.root.is_disposed() && self.control is None else { return false }
  self.control = Some(control)
  for entry in self.entries {
    if entry.active && !entry.owner.is_disposed() && !(entry.connect)(control) {
      abort("downstream Source could not connect to the application Driver")
    }
  }
  true
}

///|
fn[K] identity_of(current : Current[K]) -> DownstreamIdentity[K]? {
  match current.view() {
    CurrentReady(value, provenance) => Some({ value, provenance, })
    _ => None
  }
}

///|
pub fn[K : Eq, V, E] DownstreamRegistry::register_result(
  self : DownstreamRegistry,
  owner : @reactive.Scope,
  desired : () -> Current[K],
  run : async (K) -> Result[V, E],
  error_text : (E) -> String,
) -> Downstream[K, V] {
  if self.reconciling ||
    self.root.is_disposed() ||
    owner.is_disposed() ||
    !self.root.contains(owner) {
    abort("downstream registration requires a live owner below its registry")
  }
  let source : Source[DownstreamIdentity[K], V] = Source::new(owner)
  if self.control is Some(control) && !source.connect(control) {
    abort("downstream Source could not connect to the application Driver")
  }
  let memo = @reactive.Memo::new_by(owner, desired, fn(_, _) { false })
  let initial : DownstreamControl[K] = {
    identity: None,
    epoch: 0,
    retry: 0,
    attempted_epoch: -1,
    attempted_retry: -1,
    accepted: None,
    accepted_cycle: None,
    rejected: false,
  }
  let control = @reactive.Signal::new_by(owner, initial, fn(_, _) { false })
  let downstream : Downstream[K, V] = { owner, desired: memo, source, control, }
  let graph = self.root.graph()
  let entry : DownstreamEntry = {
    owner,
    connect: task_control => source.connect(task_control),
    prepare: () => {
      let sampled = identity_of(memo.get())
      let before = control.peek()
      submit => {
        if owner.is_disposed() {
          return false
        }
        let mut state = before
        let mut changed = false
        if sampled != state.identity {
          if state.accepted is Some(_) {
            ignore(source.retire_current())
          }
          state = {
            ..state,
            identity: sampled,
            epoch: state.epoch + 1,
            accepted: None,
            accepted_cycle: None,
            rejected: false,
          }
          control.set(state)
          changed = true
        }
        guard sampled is Some(identity) else { return changed }
        if state.attempted_epoch == state.epoch &&
          state.attempted_retry == state.retry {
          return changed
        }
        if state.accepted is Some(_) {
          ignore(source.retire_current())
        }
        let cycle = Cycle::new()
        state = {
          ..state,
          attempted_epoch: state.epoch,
          attempted_retry: state.retry,
          accepted: None,
          accepted_cycle: None,
          rejected: false,
        }
        control.set(state)
        changed = true
        guard source.replace_result(
            identity,
            cycle,
            false,
            () => run(identity.value),
            error_text,
          )
          is Some(request) else {
          control.set({ ..state, rejected: true, })
          return changed
        }
        let accepted = submit(
          @task.group([request], apply => graph.batch(apply), on_admitted=() => {
            control.set({
              ..state,
              accepted: Some(identity),
              accepted_cycle: Some(cycle),
            })
          }),
        )
        if !accepted {
          control.set({ ..state, rejected: true, })
        }
        changed
      }
    },
    active: true,
  }
  self.entries.push(entry)
  owner.on_dispose(() => {
    entry.active = false
    self.entries.retain(candidate => !physical_equal(candidate, entry))
  })
  downstream
}

///|
pub fn[K : Eq, V] DownstreamRegistry::register(
  self : DownstreamRegistry,
  owner : @reactive.Scope,
  desired : () -> Current[K],
  run : async (K) -> V,
) -> Downstream[K, V] {
  self.register_result(
    owner,
    desired,
    async fn(key : K) -> Result[V, String] { Ok(run(key)) },
    error => error,
  )
}

///|
pub fn DownstreamRegistry::reconcile(
  self : DownstreamRegistry,
  submit : (@task.Request) -> Bool,
) -> Bool {
  if self.root.is_disposed() || self.control is None {
    return false
  }
  if self.reconciling {
    abort("downstream reconciliation cannot re-enter")
  }
  self.reconciling = true
  defer {
    self.reconciling = false
  }
  let graph = self.root.graph()
  graph.batch(() => ())
  let entries = self.entries.copy()
  let prepared : Array[((@task.Request) -> Bool) -> Bool] = []
  graph.read_only(() => {
    for entry in entries {
      if entry.active && !entry.owner.is_disposed() {
        prepared.push((entry.prepare)())
      }
    }
  })
  for entry in entries {
    if !entry.active || entry.owner.is_disposed() {
      abort("downstream owner changed during sampling")
    }
  }
  graph.batch(() => {
    let mut changed = false
    for apply in prepared {
      if apply(submit) {
        changed = true
      }
    }
    changed
  })
}

///|
pub fn[K : Eq, V] Downstream::current(self : Downstream[K, V]) -> Current[V] {
  let desired = self.desired.get()
  let identity = identity_of(desired)
  let state = self.control.get()
  match identity {
    None => blocked_downstream(desired, self.source.source_id, WaitingUpstream)
    Some(value) =>
      if state.identity == Some(value) &&
        state.accepted == Some(value) &&
        state.attempted_retry == state.retry &&
        state.accepted_cycle is Some(cycle) {
        join_independent(desired, self.source.current(value, cycle), fn(
          _,
          result,
        ) {
          result
        })
      } else {
        blocked_downstream(
          desired,
          self.source.source_id,
          if state.identity == Some(value) && state.rejected {
            AdmissionRejected
          } else {
            NotAdmitted
          },
        )
      }
  }
}

///|
pub fn[K : Eq, V] Downstream::admission(
  self : Downstream[K, V],
) -> DownstreamAdmission[K] {
  let identity = identity_of(self.desired.get())
  let state = self.control.get()
  match identity {
    None => AwaitingUpstream
    Some(value) =>
      if state.identity == Some(value) &&
        state.accepted == Some(value) &&
        state.attempted_retry == state.retry &&
        state.accepted_cycle is Some(cycle) {
        Admitted(value.value, value.provenance, cycle)
      } else if state.identity == Some(value) && state.rejected {
        Rejected(value.value, value.provenance)
      } else {
        Eligible(value.value, value.provenance)
      }
  }
}

///|
pub fn[K : Eq, V] Downstream::retry(self : Downstream[K, V]) -> Bool {
  guard !self.owner.is_disposed() else { return false }
  let state = self.control.peek()
  if state.accepted is Some(identity) &&
    self.source.peek() is Pending(active, _, _) &&
    identity == active {
    return false
  }
  self.control.set({ ..state, retry: state.retry + 1, })
  true
}

///|
pub fn[K, V] Downstream::track_source(
  self : Downstream[K, V],
  registry : TraceRegistry,
  owner_id : Int,
  key_id : (K) -> Int,
) -> Bool {
  registry.track_source(self.source, owner_id, identity => {
    key_id(identity.value)
  })
}
