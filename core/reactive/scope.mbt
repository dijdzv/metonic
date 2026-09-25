///|
pub struct Scope {
  priv graph : Graph
  priv parent : Scope?
  priv children : Array[Scope]
  priv disposers : Array[() -> Unit]
  priv mut disposed : Bool
}

///|
pub fn Scope::root(graph : Graph) -> Scope {
  { graph, parent: None, children: [], disposers: [], disposed: false, }
}

///|
pub fn Scope::child(self : Scope) -> Scope {
  self.assert_alive()
  let child : Scope = {
    graph: self.graph,
    parent: Some(self),
    children: [],
    disposers: [],
    disposed: false,
  }
  self.children.push(child)
  child
}

///|
pub fn Scope::is_disposed(self : Scope) -> Bool {
  self.disposed
}

///|
pub fn Scope::graph(self : Scope) -> Graph {
  self.graph
}

///|
pub fn Scope::contains(self : Scope, dependent : Scope) -> Bool {
  self.outlives(dependent)
}

///|
fn Scope::assert_alive(self : Scope) -> Unit {
  if self.disposed {
    abort("reactive scope is disposed")
  }
}

///|
fn Scope::own(self : Scope, disposer : () -> Unit) -> Unit {
  self.assert_alive()
  self.disposers.push(disposer)
}

///|
pub fn Scope::on_dispose(self : Scope, cleanup : () -> Unit) -> Unit {
  self.own(cleanup)
}

///|
fn Scope::outlives(self : Scope, dependent : Scope) -> Bool {
  let mut current : Scope? = Some(dependent)
  while current is Some(scope) {
    if physical_equal(scope, self) {
      return true
    }
    current = scope.parent
  }
  false
}

///|
pub fn Scope::dispose(self : Scope) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  self.graph.batch(fn() {
    self.graph.untracked(fn() {
      guard_writes(fn() {
        for i = self.children.length() - 1; i >= 0; i = i - 1 {
          self.children[i].dispose()
        }
        for i = self.disposers.length() - 1; i >= 0; i = i - 1 {
          self.disposers[i]()
        }
        self.children.clear()
        self.disposers.clear()
      })
    })
  })
  if self.parent is Some(parent) {
    if !parent.disposed {
      parent.children.retain(fn(child) { !physical_equal(child, self) })
    }
  }
}
