///|
pub struct Origin {
  priv source_id : Int
  priv admission_id : Int
  priv revision : Int
  priv cycle : Cycle
} derive(Debug, Eq)

///|
pub fn Origin::source_id(self : Origin) -> Int {
  self.source_id
}

///|
pub fn Origin::admission_id(self : Origin) -> Int {
  self.admission_id
}

///|
pub fn Origin::revision(self : Origin) -> Int {
  self.revision
}

///|
pub fn Origin::cycle(self : Origin) -> Cycle {
  self.cycle
}

///|
pub struct Provenance {
  priv origins : Array[Origin]
} derive(Debug, Eq)

///|
pub fn Provenance::length(self : Provenance) -> Int {
  self.origins.length()
}

///|
pub fn Provenance::origin(self : Provenance, index : Int) -> Origin? {
  if index < 0 || index >= self.origins.length() {
    None
  } else {
    Some(self.origins[index])
  }
}

///|
pub(all) enum CurrentCause {
  IdleSource(Int)
  OtherRequest(Int)
  PendingSource(Origin)
  FailedSource(Origin, String)
  CanceledSource(Origin)
  OriginConflict(Int, Origin, Origin)
  RelatedContractMismatch
} derive(Debug, Eq)

///|
pub struct CauseSet {
  priv values : Array[CurrentCause]
} derive(Debug, Eq)

///|
pub fn CauseSet::length(self : CauseSet) -> Int {
  self.values.length()
}

///|
pub fn CauseSet::cause(self : CauseSet, index : Int) -> CurrentCause? {
  if index < 0 || index >= self.values.length() {
    None
  } else {
    Some(self.values[index])
  }
}

///|
pub(all) enum CurrentView[T] {
  CurrentIdle(CauseSet)
  CurrentBlocked(CauseSet)
  CurrentPending(CauseSet)
  CurrentReady(T, Provenance)
  CurrentFailed(CauseSet)
  CurrentCanceled(CauseSet)
} derive(Debug, Eq)

///|
enum LeafPhase {
  LeafIdle
  LeafOtherRequest
  LeafPending
  LeafReady
  LeafFailed(String)
  LeafCanceled
} derive(Debug, Eq)

///|
struct Observation {
  source_id : Int
  origin : Origin?
  phase : LeafPhase
} derive(Debug, Eq)

///|
struct EvidenceSet {
  observations : Array[Observation]
  related_mismatch : Bool
} derive(Debug, Eq)

///|
pub struct Current[T] {
  priv evidence : EvidenceSet
  priv value : T?
} derive(Debug, Eq)

///|
pub struct Related[K] {
  priv key : K
  priv cycle : Cycle
}

///|
pub struct RelatedCurrent[K, T] {
  priv contract : Related[K]
  priv current : Current[T]
}

///|
fn origin_before(left : Origin, right : Origin) -> Bool {
  if left.source_id != right.source_id {
    left.source_id < right.source_id
  } else if left.admission_id != right.admission_id {
    left.admission_id < right.admission_id
  } else if left.revision != right.revision {
    left.revision < right.revision
  } else {
    left.cycle.id < right.cycle.id
  }
}

///|
fn observation_phase_rank(phase : LeafPhase) -> Int {
  match phase {
    LeafIdle => 0
    LeafOtherRequest => 1
    LeafPending => 2
    LeafReady => 3
    LeafCanceled => 4
    LeafFailed(_) => 5
  }
}

///|
fn observation_before(left : Observation, right : Observation) -> Bool {
  if left.source_id != right.source_id {
    left.source_id < right.source_id
  } else {
    match (left.origin, right.origin) {
      (None, Some(_)) => true
      (Some(_), None) => false
      (Some(a), Some(b)) if a != b => origin_before(a, b)
      _ =>
        observation_phase_rank(left.phase) < observation_phase_rank(right.phase)
    }
  }
}

///|
fn EvidenceSet::merge(left : EvidenceSet, right : EvidenceSet) -> EvidenceSet {
  let observations = left.observations.copy()
  for item in right.observations {
    if !observations.contains(item) {
      observations.push(item)
    }
  }
  for i = 0; i < observations.length(); i = i + 1 {
    for j = i + 1; j < observations.length(); j = j + 1 {
      if observation_before(observations[j], observations[i]) {
        let old = observations[i]
        observations[i] = observations[j]
        observations[j] = old
      }
    }
  }
  {
    observations,
    related_mismatch: left.related_mismatch || right.related_mismatch,
  }
}

///|
fn cause_source(cause : CurrentCause) -> Int {
  match cause {
    IdleSource(id) | OtherRequest(id) | OriginConflict(id, _, _) => id
    PendingSource(origin) | FailedSource(origin, _) | CanceledSource(origin) =>
      origin.source_id
    RelatedContractMismatch => 0
  }
}

///|
fn cause_rank(cause : CurrentCause) -> Int {
  match cause {
    RelatedContractMismatch => 0
    IdleSource(_) => 1
    OtherRequest(_) => 2
    PendingSource(_) => 3
    CanceledSource(_) => 4
    FailedSource(_, _) => 5
    OriginConflict(_, _, _) => 6
  }
}

///|
fn cause_origin(cause : CurrentCause) -> Origin? {
  match cause {
    PendingSource(origin) | FailedSource(origin, _) | CanceledSource(origin) =>
      Some(origin)
    OriginConflict(_, first, _) => Some(first)
    _ => None
  }
}

///|
fn cause_before(left : CurrentCause, right : CurrentCause) -> Bool {
  if cause_source(left) != cause_source(right) {
    cause_source(left) < cause_source(right)
  } else if cause_rank(left) != cause_rank(right) {
    cause_rank(left) < cause_rank(right)
  } else {
    match (cause_origin(left), cause_origin(right)) {
      (Some(a), Some(b)) if a != b => origin_before(a, b)
      _ => false
    }
  }
}

///|
fn EvidenceSet::phase_and_causes(self : EvidenceSet) -> (Int, CauseSet) {
  let causes : Array[CurrentCause] = []
  let mut failed = false
  let mut canceled = false
  let mut blocked = self.related_mismatch
  let mut pending = false
  let mut ready = false
  let mut idle = false
  if self.related_mismatch {
    causes.push(RelatedContractMismatch)
  }
  for item in self.observations {
    let cause = match item.phase {
      LeafIdle => {
        idle = true
        Some(IdleSource(item.source_id))
      }
      LeafOtherRequest => {
        blocked = true
        Some(OtherRequest(item.source_id))
      }
      LeafPending => {
        pending = true
        match item.origin {
          Some(origin) => Some(PendingSource(origin))
          None => abort("pending evidence has no admitted origin")
        }
      }
      LeafReady => {
        ready = true
        None
      }
      LeafFailed(message) => {
        failed = true
        match item.origin {
          Some(origin) => Some(FailedSource(origin, message))
          None => abort("failed evidence has no admitted origin")
        }
      }
      LeafCanceled => {
        canceled = true
        match item.origin {
          Some(origin) => Some(CanceledSource(origin))
          None => abort("canceled evidence has no admitted origin")
        }
      }
    }
    match cause {
      Some(value) if !causes.contains(value) => causes.push(value)
      _ => ()
    }
  }
  for i = 0; i < self.observations.length(); i = i + 1 {
    for j = i + 1; j < self.observations.length(); j = j + 1 {
      let a = self.observations[i]
      let b = self.observations[j]
      if a.source_id == b.source_id && a.origin != b.origin {
        match (a.origin, b.origin) {
          (Some(first), Some(second)) => {
            blocked = true
            let conflict = OriginConflict(a.source_id, first, second)
            if !causes.contains(conflict) {
              causes.push(conflict)
            }
          }
          _ => ()
        }
      }
    }
  }
  for i = 0; i < causes.length(); i = i + 1 {
    for j = i + 1; j < causes.length(); j = j + 1 {
      if cause_before(causes[j], causes[i]) {
        let old = causes[i]
        causes[i] = causes[j]
        causes[j] = old
      }
    }
  }
  let phase = if failed {
    5
  } else if canceled {
    4
  } else if blocked {
    3
  } else if pending {
    2
  } else if idle && ready {
    3
  } else if ready {
    1
  } else {
    0
  }
  (phase, { values: causes, })
}

///|
pub fn[T] Current::view(self : Current[T]) -> CurrentView[T] {
  let (phase, causes) = self.evidence.phase_and_causes()
  match phase {
    5 => CurrentFailed(causes)
    4 => CurrentCanceled(causes)
    3 => CurrentBlocked(causes)
    2 => CurrentPending(causes)
    1 => {
      let value = match self.value {
        Some(value) => value
        None => abort("ready evidence has no complete value")
      }
      let origins : Array[Origin] = []
      for item in self.evidence.observations {
        match item.origin {
          Some(origin) if !origins.contains(origin) => origins.push(origin)
          _ => ()
        }
      }
      CurrentReady(value, { origins, })
    }
    _ => CurrentIdle(causes)
  }
}

///|
pub fn[A, B] Current::map(self : Current[A], f : (A) -> B) -> Current[B] {
  let value = match self.value {
    Some(value) => Some(f(value))
    None => None
  }
  { evidence: self.evidence, value, }
}

///|
pub fn[A, B, C] join_independent(
  left : Current[A],
  right : Current[B],
  combine : (A, B) -> C,
) -> Current[C] {
  let evidence = EvidenceSet::merge(left.evidence, right.evidence)
  let value = if evidence.phase_and_causes().0 == 1 {
    match (left.value, right.value) {
      (Some(a), Some(b)) => Some(combine(a, b))
      _ => abort("ready evidence has an incomplete input")
    }
  } else {
    None
  }
  { evidence, value, }
}

///|
pub fn[K] Related::new(key : K, cycle : Cycle) -> Related[K] {
  { key, cycle, }
}

///|
pub fn[K : Eq, V] Related::read(
  self : Related[K],
  source : Source[K, V],
) -> RelatedCurrent[K, V] {
  { contract: self, current: source.current(self.key, self.cycle), }
}

///|
pub fn[K, T] RelatedCurrent::current(self : RelatedCurrent[K, T]) -> Current[T] {
  self.current
}

///|
pub fn[K, A, B] RelatedCurrent::map(
  self : RelatedCurrent[K, A],
  f : (A) -> B,
) -> RelatedCurrent[K, B] {
  { contract: self.contract, current: self.current.map(f), }
}

///|
pub fn[K : Eq, A, B, C] join_related(
  left : RelatedCurrent[K, A],
  right : RelatedCurrent[K, B],
  combine : (A, B) -> C,
) -> RelatedCurrent[K, C] {
  let contract = left.contract
  let current = if contract.key == right.contract.key &&
    contract.cycle == right.contract.cycle {
    join_independent(left.current, right.current, combine)
  } else {
    let combined = EvidenceSet::merge(
      left.current.evidence,
      right.current.evidence,
    )
    let evidence = {
      observations: combined.observations,
      related_mismatch: true,
    }
    { evidence, value: None, }
  }
  { contract, current, }
}

///|
pub fn[K : Eq, V] Source::current(
  self : Source[K, V],
  key : K,
  cycle : Cycle,
) -> Current[V] {
  let state = self.state.get()
  let actual_cycle = match state {
    Idle => None
    Pending(_, cycle, _)
    | Ready(_, cycle, _, _)
    | Failed(_, cycle, _, _)
    | Canceled(_, cycle, _) => Some(cycle)
  }
  let origin = match actual_cycle {
    Some(actual) =>
      Some({
        source_id: self.source_id,
        admission_id: self.admission_id.val,
        revision: self.state_revision.val,
        cycle: actual,
      })
    None => None
  }
  let (phase, value) = match state {
    Idle => (LeafIdle, None)
    Pending(active_key, active_cycle, _) if active_key == key &&
      active_cycle == cycle => (LeafPending, None)
    Ready(active_key, active_cycle, value, _) if active_key == key &&
      active_cycle == cycle => (LeafReady, Some(value))
    Failed(active_key, active_cycle, message, _) if active_key == key &&
      active_cycle == cycle => (LeafFailed(message), None)
    Canceled(active_key, active_cycle, _) if active_key == key &&
      active_cycle == cycle => (LeafCanceled, None)
    _ => (LeafOtherRequest, None)
  }
  {
    evidence: {
      observations: [{ source_id: self.source_id, origin, phase, }],
      related_mismatch: false,
    },
    value,
  }
}
