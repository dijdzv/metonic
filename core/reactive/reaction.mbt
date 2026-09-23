///|
pub struct Effect {
  priv node : Node
  priv callback : (Effect) -> Unit
  priv cleanups : Array[() -> Unit]
  priv mut initialized : Bool
}

///|
pub fn Effect::new(scope : Scope, callback : (Effect) -> Unit) -> Effect {
  scope.assert_alive()
  let node = Node::new(scope, true)
  node.dirty = true
  let effect : Effect = { node, callback, cleanups: [], initialized: false, }
  node.run = Some(fn() { effect.run() })
  scope.own(fn() { effect.dispose() })
  node.graph.queue(node)
  node.graph.flush()
  effect
}

///|
fn Effect::run_cleanups(self : Effect) -> Unit {
  let graph = self.node.graph
  let pending : Array[() -> Unit] = []
  for cleanup in self.cleanups {
    pending.push(cleanup)
  }
  self.cleanups.clear()
  let previous = graph.writes_blocked
  graph.writes_blocked = true
  graph.untracked(fn() {
    guard_writes(fn() {
      for i = pending.length() - 1; i >= 0; i = i - 1 {
        pending[i]()
      }
    })
  })
  graph.writes_blocked = previous
}

///|
fn Effect::run(self : Effect) -> Unit {
  let node = self.node
  if node.disposed {
    return
  }
  if self.initialized && !node.dependencies_changed() {
    node.dirty = false
    return
  }
  self.run_cleanups()
  if node.disposed {
    return
  }
  node.detach()
  node.evaluating = true
  let previous = node.graph.active
  let previous_graph = active_graph.val
  node.graph.active = Some(node)
  active_graph.val = Some(node.graph)
  guard_writes(fn() { (self.callback)(self) })
  node.graph.active = previous
  active_graph.val = previous_graph
  node.evaluating = false
  if !node.disposed {
    node.capture_versions()
    node.dirty = false
    self.initialized = true
  }
}

///|
pub fn Effect::on_cleanup(self : Effect, cleanup : () -> Unit) -> Unit {
  if self.node.disposed || !self.node.evaluating {
    abort("cleanup registration requires a running reactive effect")
  }
  self.cleanups.push(cleanup)
}

///|
pub fn Effect::dispose(self : Effect) -> Unit {
  if self.node.disposed {
    return
  }
  self.node.dispose()
  self.run_cleanups()
}

///|
pub struct Binding[T] {
  priv effect : Effect
  priv last : Ref[T?]
}

///|
pub fn[T : Eq] Binding::new(
  scope : Scope,
  read : () -> T,
  apply : (T) -> Unit,
) -> Binding[T] {
  Binding::new_by(scope, read, apply, fn(a, b) { a == b })
}

///|
pub fn[T] Binding::new_by(
  scope : Scope,
  read : () -> T,
  apply : (T) -> Unit,
  equal : (T, T) -> Bool,
) -> Binding[T] {
  let last : Ref[T?] = Ref(None)
  let effect = Effect::new(scope, fn(_) {
    let next = read()
    match last.val {
      Some(old) =>
        if !scope.graph.untracked(fn() { equal(old, next) }) {
          scope.graph.untracked(fn() { apply(next) })
          last.val = Some(next)
        }
      None => {
        scope.graph.untracked(fn() { apply(next) })
        last.val = Some(next)
      }
    }
  })
  { effect, last, }
}

///|
pub fn[T] Binding::dispose(self : Binding[T]) -> Unit {
  self.effect.dispose()
}

///|
pub fn[T] Binding::current(self : Binding[T]) -> T? {
  self.last.val
}
