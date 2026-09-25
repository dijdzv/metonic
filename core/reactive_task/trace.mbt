///|
pub(all) enum TraceKind {
  RequestAdmitted
  PendingTransition
  ReadyTransition
  FailedTransition
  ExpectedFailure
  UnexpectedFailure
  CanceledTransition
  CancellationRequested
  AdmissionRejected
  ProgressRejected
  CompletionRejected
  FailureRejected
  OwnerDisposed
  SourceDisposed
  CleanupJoined
} derive(Debug, Eq)

///|
pub(all) struct TraceEvent {
  sequence : Int
  kind : TraceKind
  source_id : Int
  operation_id : Int
  owner_id : Int
  key_id : Int?
  cycle_id : Int?
  admission_id : Int
  revision : Int
  driver_generation : Int?
  cleanup_pending : Array[Int]
  denial : @task.AdmissionDenial?
} derive(Debug, Eq)

///|
pub(all) struct TraceSource {
  source_id : Int
  operation_id : Int
  owner_id : Int
  key_id : Int?
  cycle_id : Int?
  admission_id : Int
  revision : Int
  phase : String
  cleanup_pending : Array[Int]
} derive(Debug, Eq)

///|
pub(all) enum TraceOwnerKind {
  ApplicationOwner
  ComponentOwner
} derive(Debug, Eq)

///|
pub(all) struct TraceOwner {
  id : Int
  parent_id : Int?
  kind : TraceOwnerKind
  generation : Int
} derive(Debug, Eq)

///|
pub(all) struct TraceOrigin {
  source_id : Int
  admission_id : Int
  revision : Int
  cycle_id : Int
} derive(Debug, Eq)

///|
pub(all) enum TraceCause {
  IdleCause(Int)
  OtherRequestCause(Int)
  PendingCause(TraceOrigin)
  FailedCause(TraceOrigin)
  CanceledCause(TraceOrigin)
  ConflictCause(Int, TraceOrigin, TraceOrigin)
  RelatedMismatchCause
  DownstreamCause(Int, DownstreamBlock)
} derive(Debug, Eq)

///|
pub(all) struct TraceDerived {
  id : Int
  owner_id : Int
  phase : String
  causes : Array[TraceCause]
  origins : Array[TraceOrigin]
} derive(Debug, Eq)

///|
priv struct TraceOwnerRegistration {
  scope : @reactive.Scope
  data : TraceOwner
  mut active : Bool
}

///|
priv struct TraceRegistration {
  operation : @task.Operation
  pending_cleanup : Array[Int]
  mut active : Bool
  read : () -> TraceSource
}

///|
priv struct TraceDerivedRegistration {
  id : Int
  owner_id : Int
  read : () -> TraceDerived
}

///|
pub struct TraceRegistry {
  priv capacity : Int
  priv events : Array[TraceEvent]
  priv sources : Array[TraceRegistration]
  priv owners : Array[TraceOwnerRegistration]
  priv derived : Array[TraceDerived]
  priv derived_reads : Array[TraceDerivedRegistration]
  priv mut next_owner_id : Int
  priv mut sequence : Int
  priv mut dropped : Int
}

///|
pub fn TraceRegistry::new(capacity : Int) -> TraceRegistry {
  if capacity < 1 || capacity > 1024 {
    abort("diagnostic history capacity must be between 1 and 1024")
  }
  {
    capacity,
    events: [],
    sources: [],
    owners: [],
    derived: [],
    derived_reads: [],
    next_owner_id: 0,
    sequence: 0,
    dropped: 0,
  }
}

///|
pub fn TraceRegistry::events(self : TraceRegistry) -> Array[TraceEvent] {
  self.events.copy()
}

///|
pub fn TraceRegistry::sources(self : TraceRegistry) -> Array[TraceSource] {
  self.sources.filter(entry => entry.active).map(entry => (entry.read)())
}

///|
pub fn TraceRegistry::owners(self : TraceRegistry) -> Array[TraceOwner] {
  self.owners.filter(entry => entry.active).map(entry => entry.data)
}

///|
pub fn TraceRegistry::derived(self : TraceRegistry) -> Array[TraceDerived] {
  let result = self.derived.copy()
  for entry in self.derived_reads {
    result.push((entry.read)())
  }
  result
}

///|
pub fn TraceRegistry::track_owner(
  self : TraceRegistry,
  scope : @reactive.Scope,
  parent_id : Int?,
  kind : TraceOwnerKind,
  generation : Int,
) -> Int? {
  guard !scope.is_disposed() &&
    generation >= 0 &&
    !self.owners.any(entry => entry.active && physical_equal(entry.scope, scope)) else {
    return None
  }
  let parent_valid = match parent_id {
    Some(id) =>
      self.owners.any(entry => {
        entry.active && entry.data.id == id && entry.scope.contains(scope)
      })
    None => true
  }
  guard parent_valid else { return None }
  guard self.next_owner_id < 0x7fffffff else {
    abort("diagnostic owner identity exhausted")
  }
  self.next_owner_id += 1
  let data : TraceOwner = {
    id: self.next_owner_id,
    parent_id,
    kind,
    generation,
  }
  let entry : TraceOwnerRegistration = { scope, data, active: true, }
  self.owners.push(entry)
  scope.on_dispose(() => {
    if entry.active {
      entry.active = false
      self.record(OwnerDisposed, {
        source_id: 0,
        operation_id: 0,
        owner_id: data.id,
        key_id: None,
        cycle_id: None,
        admission_id: 0,
        revision: 0,
        phase: "disposed",
        cleanup_pending: [],
      })
      self.owners.retain(candidate => !physical_equal(candidate, entry))
      self.derived.retain(item => item.owner_id != data.id)
      self.derived_reads.retain(item => item.owner_id != data.id)
    }
  })
  Some(data.id)
}

///|
fn trace_origin(origin : Origin) -> TraceOrigin {
  {
    source_id: origin.source_id,
    admission_id: origin.admission_id,
    revision: origin.revision,
    cycle_id: origin.cycle.id,
  }
}

///|
fn trace_causes(causes : CauseSet) -> Array[TraceCause] {
  causes.values.map(cause => {
    match cause {
      IdleSource(id) => IdleCause(id)
      OtherRequest(id) => OtherRequestCause(id)
      PendingSource(origin) => PendingCause(trace_origin(origin))
      FailedSource(origin, _) => FailedCause(trace_origin(origin))
      CanceledSource(origin) => CanceledCause(trace_origin(origin))
      OriginConflict(id, first, second) =>
        ConflictCause(id, trace_origin(first), trace_origin(second))
      RelatedContractMismatch => RelatedMismatchCause
      DownstreamBlocked(id, reason) => DownstreamCause(id, reason)
    }
  })
}

///|
fn[T] trace_derived(
  id : Int,
  owner_id : Int,
  current : Current[T],
) -> TraceDerived {
  let (phase, causes, origins) = match current.view() {
    CurrentIdle(causes) => ("idle", trace_causes(causes), [])
    CurrentBlocked(causes) => ("blocked", trace_causes(causes), [])
    CurrentPending(causes) => ("pending", trace_causes(causes), [])
    CurrentReady(_, provenance) =>
      ("ready", [], provenance.origins.map(trace_origin))
    CurrentFailed(causes) => ("failed", trace_causes(causes), [])
    CurrentCanceled(causes) => ("canceled", trace_causes(causes), [])
  }
  { id, owner_id, phase, causes, origins, }
}

///|
pub fn[T] TraceRegistry::track_derived(
  self : TraceRegistry,
  scope : @reactive.Scope,
  id : Int,
  owner_id : Int,
  sample : () -> Current[T],
) -> Bool {
  guard id > 0 &&
    !scope.is_disposed() &&
    self.owners.any(entry => {
      entry.active && entry.data.id == owner_id && entry.scope.contains(scope)
    }) &&
    !self.derived.any(item => item.id == id) &&
    !self.derived_reads.any(item => item.id == id) else {
    return false
  }
  let read = () => {
    scope.graph().untracked(() => trace_derived(id, owner_id, sample()))
  }
  self.derived_reads.push({ id, owner_id, read, })
  scope.on_dispose(() => self.derived_reads.retain(item => item.id != id))
  true
}

///|
pub fn[T] TraceRegistry::observe_derived(
  self : TraceRegistry,
  id : Int,
  owner_id : Int,
  current : Current[T],
) -> Bool {
  if id < 1 ||
    !self.owners.any(entry => entry.active && entry.data.id == owner_id) ||
    self.derived_reads.any(item => item.id == id) {
    return false
  }
  let sampled = trace_derived(id, owner_id, current)
  for index, item in self.derived {
    if item.id == id {
      if item.owner_id != owner_id {
        return false
      }
      self.derived[index] = sampled
      return true
    }
  }
  self.derived.push(sampled)
  true
}

///|
pub fn TraceRegistry::dropped(self : TraceRegistry) -> Int {
  self.dropped
}

///|
fn TraceRegistry::record(
  self : TraceRegistry,
  kind : TraceKind,
  source : TraceSource,
  driver_generation? : Int? = None,
  denial? : @task.AdmissionDenial? = None,
) -> Unit {
  if self.sequence == 0x7fffffff {
    abort("diagnostic sequence exhausted")
  }
  self.sequence += 1
  if self.events.length() == self.capacity {
    ignore(self.events.remove(0))
    self.dropped += 1
  }
  self.events.push({
    sequence: self.sequence,
    kind,
    source_id: source.source_id,
    operation_id: source.operation_id,
    owner_id: source.owner_id,
    key_id: source.key_id,
    cycle_id: source.cycle_id,
    admission_id: source.admission_id,
    revision: source.revision,
    driver_generation,
    cleanup_pending: source.cleanup_pending.copy(),
    denial,
  })
}

///|
fn[K, V] trace_source_state(
  source : Source[K, V],
  owner_id : Int,
  key_id : (K) -> Int,
  state : AsyncState[K, V],
  pending_cleanup : Array[Int],
) -> TraceSource {
  let (key, cycle, phase) = match state {
    Idle => (None, None, "idle")
    Pending(key, cycle, _) => (Some(key_id(key)), Some(cycle.id), "pending")
    Ready(key, cycle, _, _) => (Some(key_id(key)), Some(cycle.id), "ready")
    Failed(key, cycle, _, _) => (Some(key_id(key)), Some(cycle.id), "failed")
    Canceled(key, cycle, _) => (Some(key_id(key)), Some(cycle.id), "canceled")
  }
  {
    source_id: source.source_id,
    operation_id: source.resource.operation.id(),
    owner_id,
    key_id: key,
    cycle_id: cycle,
    admission_id: source.admission_id.val,
    revision: source.state_revision.val,
    phase,
    cleanup_pending: pending_cleanup.copy(),
  }
}

///|
pub fn[K, V] TraceRegistry::track_source(
  self : TraceRegistry,
  source : Source[K, V],
  owner_id : Int,
  key_id : (K) -> Int,
) -> Bool {
  if source.scope.is_disposed() || source.trace is Some(_) {
    return false
  }
  if !self.owners.any(entry => {
      entry.active &&
      entry.data.id == owner_id &&
      entry.scope.contains(source.scope)
    }) {
    return false
  }
  let pending_cleanup : Array[Int] = []
  let read = () => {
    source.scope
    .graph()
    .untracked(() => {
      trace_source_state(
        source,
        owner_id,
        key_id,
        source.peek(),
        pending_cleanup,
      )
    })
  }
  let entry : TraceRegistration = {
    operation: source.resource.operation,
    pending_cleanup,
    active: true,
    read,
  }
  self.sources.push(entry)
  source.trace = Some(kind => self.record(kind, read()))
  source.resource.on_rejected = Some(kind => {
    if source.trace is Some(record) {
      record(kind)
    }
  })
  source.scope.on_dispose(() => {
    if entry.active {
      self.record(SourceDisposed, read())
      entry.active = false
      self.sources.retain(candidate => !physical_equal(candidate, entry))
      source.trace = None
      source.resource.on_rejected = None
    }
  })
  true
}

///|
pub fn TraceRegistry::driver_event(
  self : TraceRegistry,
  operation : @task.Operation,
  event : @task.DriverEvent,
) -> Unit {
  for entry in self.sources {
    if entry.active && entry.operation == operation {
      let source = (entry.read)()
      match event {
        @task.RequestAdmitted(generation) =>
          self.record(
            RequestAdmitted,
            source,
            driver_generation=Some(generation),
          )
        @task.RequestDenied(reason) =>
          self.record(AdmissionRejected, source, denial=Some(reason))
        @task.CancelRequested(generation) => {
          if !entry.pending_cleanup.contains(generation) {
            entry.pending_cleanup.push(generation)
          }
          self.record(
            CancellationRequested,
            (entry.read)(),
            driver_generation=Some(generation),
          )
        }
        @task.CleanupJoined(generation) => {
          entry.pending_cleanup.retain(item => item != generation)
          self.record(
            CleanupJoined,
            (entry.read)(),
            driver_generation=Some(generation),
          )
        }
        @task.ProgressDropped(generation) =>
          self.record(
            ProgressRejected,
            source,
            driver_generation=Some(generation),
          )
        @task.CompletionDropped(generation) =>
          self.record(
            CompletionRejected,
            source,
            driver_generation=Some(generation),
          )
      }
    }
  }
}
