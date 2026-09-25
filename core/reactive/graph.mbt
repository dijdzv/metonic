///|
pub struct Graph {
  priv mut active : Node?
  priv mut batch_depth : Int
  priv mut flushing : Bool
  priv mut writes_blocked : Bool
  priv pending : Array[Node]
  priv mut next_id : Int
}

///|
let active_graph : Ref[Graph?] = Ref(None)

///|
let write_guard_depth : Ref[Int] = Ref(0)

///|
fn[T] guard_writes(f : () -> T) -> T {
  write_guard_depth.val = write_guard_depth.val + 1
  let result = f()
  write_guard_depth.val = write_guard_depth.val - 1
  result
}

///|
priv struct Node {
  graph : Graph
  scope : Scope
  id : Int
  is_reaction : Bool
  deps : Array[Node]
  observers : Array[Node]
  seen_versions : Array[Int]
  mut version : Int
  mut dirty : Bool
  mut queued : Bool
  mut evaluating : Bool
  mut disposed : Bool
  mut refresh : (() -> Unit)?
  mut run : (() -> Unit)?
}

///|
pub fn Graph::new() -> Graph {
  {
    active: None,
    batch_depth: 0,
    flushing: false,
    writes_blocked: false,
    pending: [],
    next_id: 0,
  }
}

///|
fn Node::new(scope : Scope, is_reaction : Bool) -> Node {
  let graph = scope.graph
  let id = graph.next_id
  graph.next_id = id + 1
  {
    graph,
    scope,
    id,
    is_reaction,
    deps: [],
    observers: [],
    seen_versions: [],
    version: 0,
    dirty: false,
    queued: false,
    evaluating: false,
    disposed: false,
    refresh: None,
    run: None,
  }
}

///|
fn Node::detach(self : Node) -> Unit {
  for dep in self.deps {
    dep.observers.retain(fn(observer) { observer.id != self.id })
  }
  self.deps.clear()
  self.seen_versions.clear()
}

///|
fn Node::depends_on(self : Node, target : Int, seen : Array[Int]) -> Bool {
  if self.id == target {
    return true
  }
  if seen.contains(self.id) {
    return false
  }
  seen.push(self.id)
  for dependency in self.deps {
    if dependency.depends_on(target, seen) {
      return true
    }
  }
  false
}

///|
fn Node::dispose(self : Node) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  self.run = None
  self.refresh = None
  self.detach()
  for observer in self.observers {
    observer.deps.retain(fn(dep) { dep.id != self.id })
    observer.dirty = true
    observer.graph.queue(observer)
  }
  self.observers.clear()
}

///|
fn Graph::track(self : Graph, dependency : Node) -> Unit {
  if active_graph.val is Some(owner) {
    if !physical_equal(owner, self) {
      abort("reactive dependencies cannot cross graphs")
    }
  }
  if self.active is Some(observer) {
    if observer.id == dependency.id {
      abort("reactive cycle: node depends on itself")
    }
    if !dependency.scope.outlives(observer.scope) {
      abort("reactive dependency cannot have a shorter scope")
    }
    if !observer.disposed {
      let mut already_tracked = false
      for dep in observer.deps {
        if dep.id == dependency.id {
          already_tracked = true
          break
        }
      }
      if !already_tracked {
        observer.deps.push(dependency)
        dependency.observers.push(observer)
      }
    }
  }
}

///|
fn Graph::invalidate(self : Graph, source : Node) -> Unit {
  for observer in source.observers {
    if !observer.disposed && !observer.dirty {
      observer.dirty = true
      self.queue(observer)
      self.invalidate(observer)
    }
  }
}

///|
fn Graph::queue(self : Graph, node : Node) -> Unit {
  if node.is_reaction && !node.queued && !node.disposed {
    node.queued = true
    self.pending.push(node)
  }
}

///|
fn Graph::ensure_current(self : Graph, node : Node) -> Unit {
  let _ = self
  if node.disposed {
    abort("reactive dependency is disposed")
  }
  if node.evaluating {
    abort("reactive cycle detected")
  }
  if node.dirty {
    if node.refresh is Some(refresh) {
      refresh()
    }
  }
}

///|
fn Node::dependencies_changed(self : Node) -> Bool {
  if self.deps.length() != self.seen_versions.length() {
    return true
  }
  for i in 0..<self.deps.length() {
    self.graph.ensure_current(self.deps[i])
    if self.deps[i].version != self.seen_versions[i] {
      return true
    }
  }
  false
}

///|
fn Node::capture_versions(self : Node) -> Unit {
  self.seen_versions.clear()
  for dep in self.deps {
    self.seen_versions.push(dep.version)
  }
}

///|
fn Graph::flush(self : Graph) -> Unit {
  if self.batch_depth > 0 || self.flushing {
    return
  }
  self.flushing = true
  let mut cursor = 0
  while cursor < self.pending.length() {
    let node = self.pending[cursor]
    cursor = cursor + 1
    node.queued = false
    if !node.disposed && node.dirty {
      if node.run is Some(run) {
        run()
      }
    }
  }
  self.pending.clear()
  self.flushing = false
}

///|
pub fn[T] Graph::batch(self : Graph, f : () -> T) -> T {
  self.batch_depth = self.batch_depth + 1
  let result = f()
  self.batch_depth = self.batch_depth - 1
  self.flush()
  result
}

///|
pub fn[T] Graph::untracked(self : Graph, f : () -> T) -> T {
  if active_graph.val is Some(owner) {
    if !physical_equal(owner, self) {
      abort("untracked reads must use the evaluating graph")
    }
  }
  let previous = self.active
  let previous_graph = active_graph.val
  self.active = None
  active_graph.val = None
  let result = f()
  self.active = previous
  active_graph.val = previous_graph
  result
}

///|
pub fn[T] Graph::read_only(self : Graph, f : () -> T) -> T {
  let _ = self
  guard_writes(f)
}

///|
fn Graph::assert_can_write(self : Graph) -> Unit {
  if write_guard_depth.val > 0 || self.writes_blocked {
    abort("reactive writes are not allowed during evaluation or cleanup")
  }
}
