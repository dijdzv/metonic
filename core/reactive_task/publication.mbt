///|
/// One complete display value and its Source origins. The value must be
/// immutable or copied before publication.
pub(all) struct Completed[T] {
  value : T
  provenance : Provenance
} derive(Debug, Eq)

///|
/// The current derived state and an optional earlier complete display for
/// exactly the same semantic demand.
pub(all) struct Published[K, T] {
  demand : K
  current : CurrentView[T]
  previous : Completed[T]?
} derive(Debug, Eq)

///|
struct PublicationEntry {
  owner : @reactive.Scope
  signal_id : Int
  depends_on : (Int) -> Bool
  prepare : () -> () -> Bool
  mut active : Bool
}

///|
/// Registers display snapshots under one application graph. The host calls
/// publish after applying an input or completion and before rendering.
pub struct PublicationRegistry {
  priv root : @reactive.Scope
  priv entries : Array[PublicationEntry]
  priv mut publishing : Bool
}

///|
pub struct Publication[K, T] {
  priv state : @reactive.Signal[Published[K, T]?]
}

///|
let sampling_publication : Ref[Bool] = Ref(false)

///|
pub fn PublicationRegistry::new(root : @reactive.Scope) -> PublicationRegistry {
  if root.is_disposed() {
    abort("publication registry requires a live root scope")
  }
  { root, entries: [], publishing: false, }
}

///|
pub fn[K, T] Publication::get(self : Publication[K, T]) -> Published[K, T]? {
  if sampling_publication.val {
    abort("publication cannot feed another publication input")
  }
  self.state.get()
}

///|
pub fn[K, T] Publication::peek(self : Publication[K, T]) -> Published[K, T]? {
  if sampling_publication.val {
    abort("publication cannot feed another publication input")
  }
  self.state.peek()
}

///|
/// Register a pure derivation owned by a live child Scope. Its demand must
/// include every identity change that invalidates an earlier whole display.
/// The sample must return immutable or copy-owned K and T values, and it may
/// not read any Publication output or perform I/O or reactive writes.
pub fn[K : Eq, T : Eq] PublicationRegistry::register(
  self : PublicationRegistry,
  owner : @reactive.Scope,
  sample : () -> (K, Current[T]),
) -> Publication[K, T] {
  if self.publishing ||
    self.root.is_disposed() ||
    owner.is_disposed() ||
    !self.root.contains(owner) {
    abort("publication registration requires a live owner below its registry")
  }
  let state = @reactive.Signal::new_by(owner, None, fn(_, _) { false })
  let memo = @reactive.Memo::new_by(owner, sample, fn(_, _) { false })
  let last_ready : Ref[(K, Completed[T])?] = Ref(None)
  let publication : Publication[K, T] = { state, }
  let entry : PublicationEntry = {
    owner,
    signal_id: state.node_id(),
    depends_on: target => memo.depends_on_node_id(target),
    prepare: () => {
      let (demand, current) = memo.get()
      let view = current.view()
      let previous = match view {
        CurrentReady(_, _) => None
        _ =>
          match last_ready.val {
            Some((saved_demand, completed)) if saved_demand == demand =>
              Some(completed)
            _ => None
          }
      }
      let next = Published::{ demand, current: view, previous, }
      let next_last = match view {
        CurrentReady(value, provenance) =>
          Some((demand, Completed::{ value, provenance, }))
        _ =>
          match previous {
            Some(completed) => Some((demand, completed))
            None => None
          }
      }
      let changed = state.peek() != Some(next)
      () => {
        last_ready.val = next_last
        if changed {
          state.set(Some(next))
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
  publication
}

///|
pub fn PublicationRegistry::publish(self : PublicationRegistry) -> Bool {
  if self.root.is_disposed() {
    return false
  }
  if self.publishing || sampling_publication.val {
    abort("publication round cannot re-enter")
  }
  self.publishing = true
  defer {
    self.publishing = false
    sampling_publication.val = false
  }
  let graph = self.root.graph()
  graph.batch(() => ())
  let entries = self.entries.copy()
  let prepared : Array[() -> Bool] = []
  sampling_publication.val = true
  graph.read_only(() => {
    for entry in entries {
      if entry.active && !entry.owner.is_disposed() {
        prepared.push((entry.prepare)())
      }
    }
  })
  sampling_publication.val = false
  for entry in entries {
    if !entry.active || entry.owner.is_disposed() {
      abort("publication owner changed during sampling")
    }
  }
  for entry in entries {
    if entry.active && !entry.owner.is_disposed() {
      for other in entries {
        if other.active &&
          !other.owner.is_disposed() &&
          (entry.depends_on)(other.signal_id) {
          abort("publication input depends on a published output")
        }
      }
    }
  }
  graph.batch(() => {
    let mut changed = false
    for commit in prepared {
      if commit() {
        changed = true
      }
    }
    changed
  })
}
