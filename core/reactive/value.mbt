///|
pub struct Signal[T] {
  priv node : Node
  priv mut value : T
  priv equal : (T, T) -> Bool
}

///|
pub fn[T : Eq] Signal::new(scope : Scope, initial : T) -> Signal[T] {
  Signal::new_by(scope, initial, fn(a, b) { a == b })
}

///|
pub fn[T] Signal::new_by(
  scope : Scope,
  initial : T,
  equal : (T, T) -> Bool,
) -> Signal[T] {
  let signal = Signal::new_unowned_by(scope, initial, equal)
  scope.own(fn() { signal.node.dispose() })
  signal
}

///|
fn[T] Signal::new_unowned_by(
  scope : Scope,
  initial : T,
  equal : (T, T) -> Bool,
) -> Signal[T] {
  scope.assert_alive()
  let node = Node::new(scope, false)
  { node, value: initial, equal, }
}

///|
pub fn[T] Signal::get(self : Signal[T]) -> T {
  if self.node.disposed {
    abort("reactive signal is disposed")
  }
  self.node.graph.track(self.node)
  self.value
}

///|
pub fn[T] Signal::peek(self : Signal[T]) -> T {
  if self.node.disposed {
    abort("reactive signal is disposed")
  }
  self.value
}

///|
pub fn[T] Signal::node_id(self : Signal[T]) -> Int {
  self.node.id
}

///|
pub fn[T] Signal::set(self : Signal[T], next : T) -> Unit {
  if self.node.disposed {
    abort("reactive signal is disposed")
  }
  self.node.graph.assert_can_write()
  if guard_writes(fn() { (self.equal)(self.value, next) }) {
    return
  }
  self.value = next
  self.node.version = self.node.version + 1
  self.node.graph.invalidate(self.node)
  self.node.graph.flush()
}

///|
pub fn[T] Signal::update(self : Signal[T], f : (T) -> T) -> Unit {
  let next = guard_writes(fn() { f(self.peek()) })
  self.set(next)
}

///|
pub struct Memo[T] {
  priv node : Node
  priv compute : () -> T
  priv equal : (T, T) -> Bool
  priv mut value : T?
}

///|
pub fn[T : Eq] Memo::new(scope : Scope, compute : () -> T) -> Memo[T] {
  Memo::new_by(scope, compute, fn(a, b) { a == b })
}

///|
pub fn[T] Memo::new_by(
  scope : Scope,
  compute : () -> T,
  equal : (T, T) -> Bool,
) -> Memo[T] {
  scope.assert_alive()
  let node = Node::new(scope, false)
  node.dirty = true
  let memo : Memo[T] = { node, compute, equal, value: None, }
  node.refresh = Some(fn() { memo.refresh() })
  scope.own(fn() { node.dispose() })
  memo
}

///|
fn[T] Memo::refresh(self : Memo[T]) -> Unit {
  let node = self.node
  if node.evaluating {
    abort("reactive memo cycle detected")
  }
  if self.value is Some(_) && !node.dependencies_changed() {
    node.dirty = false
    return
  }
  node.evaluating = true
  node.detach()
  let previous = node.graph.active
  let previous_graph = active_graph.val
  node.graph.active = Some(node)
  active_graph.val = Some(node.graph)
  let next = guard_writes(self.compute)
  node.graph.active = previous
  active_graph.val = previous_graph
  node.evaluating = false
  if node.disposed {
    abort("reactive memo was disposed during evaluation")
  }
  match self.value {
    Some(old) =>
      if !guard_writes(fn() { (self.equal)(old, next) }) {
        self.value = Some(next)
        node.version = node.version + 1
      }
    None => {
      self.value = Some(next)
      node.version = node.version + 1
    }
  }
  node.capture_versions()
  node.dirty = false
}

///|
pub fn[T] Memo::get(self : Memo[T]) -> T {
  self.node.graph.ensure_current(self.node)
  self.node.graph.track(self.node)
  match self.value {
    Some(value) => value
    None => abort("reactive memo was not initialized")
  }
}

///|
pub fn[T] Memo::peek(self : Memo[T]) -> T {
  self.node.graph.ensure_current(self.node)
  match self.value {
    Some(value) => value
    None => abort("reactive memo was not initialized")
  }
}

///|
pub fn[T] Memo::depends_on_node_id(self : Memo[T], target : Int) -> Bool {
  let seen : Array[Int] = []
  self.node.depends_on(target, seen)
}
