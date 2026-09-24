///|
pub(all) struct PairSnapshot[K, A, B] {
  key : K
  cycle : Cycle
  left : A
  right : B
} derive(Debug, Eq)

///|
pub(all) enum PairFailure {
  Left(String)
  Right(String)
  Both(String, String)
} derive(Debug, Eq)

///|
pub(all) enum PairView[K, A, B] {
  PairIdle
  PairPending(K, Cycle, PairSnapshot[K, A, B]?)
  PairReady(K, Cycle, A, B)
  PairFailed(K, Cycle, PairFailure, PairSnapshot[K, A, B]?)
  PairCanceled(K, Cycle, PairSnapshot[K, A, B]?)
} derive(Debug, Eq)

///|
fn[K : Eq, V] prior_for_cycle(
  state : AsyncState[K, V],
  key : K,
  cycle : Cycle,
) -> Snapshot[K, V]? {
  match state {
    Pending(current, active, previous)
    | Ready(current, active, _, previous)
    | Failed(current, active, _, previous)
    | Canceled(current, active, previous) if current == key && active == cycle =>
      previous
    _ => None
  }
}

///|
fn[K : Eq, A, B] prior_pair(
  key : K,
  cycle : Cycle,
  left : AsyncState[K, A],
  right : AsyncState[K, B],
) -> PairSnapshot[K, A, B]? {
  match
    (prior_for_cycle(left, key, cycle), prior_for_cycle(right, key, cycle)) {
    (Some(a), Some(b)) if a.key == key && b.key == key && a.cycle == b.cycle =>
      Some({ key, cycle: a.cycle, left: a.value, right: b.value, })
    _ => None
  }
}

///|
pub fn[K : Eq, A, B] derive_pair(
  key : K,
  cycle : Cycle,
  left : AsyncState[K, A],
  right : AsyncState[K, B],
) -> PairView[K, A, B] {
  let previous = prior_pair(key, cycle, left, right)
  match (left, right) {
    (Ready(left_key, left_cycle, a, _), Ready(right_key, right_cycle, b, _)) if left_key ==
      key &&
      right_key == key &&
      left_cycle == cycle &&
      right_cycle == cycle => PairReady(key, cycle, a, b)
    (
      Failed(left_key, left_cycle, left_error, _),
      Failed(right_key, right_cycle, right_error, _),
    ) if left_key == key &&
      right_key == key &&
      left_cycle == cycle &&
      right_cycle == cycle =>
      PairFailed(key, cycle, Both(left_error, right_error), previous)
    (Failed(current, active, message, _), _) if current == key &&
      active == cycle => PairFailed(key, cycle, Left(message), previous)
    (_, Failed(current, active, message, _)) if current == key &&
      active == cycle => PairFailed(key, cycle, Right(message), previous)
    (Canceled(current, active, _), _) if current == key && active == cycle =>
      PairCanceled(key, cycle, previous)
    (_, Canceled(current, active, _)) if current == key && active == cycle =>
      PairCanceled(key, cycle, previous)
    (Idle, Idle) => PairIdle
    _ => PairPending(key, cycle, previous)
  }
}
