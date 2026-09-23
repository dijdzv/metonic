///|
test "signal memo and binding suppress equal observations" {
  let graph = Graph::new()
  let scope = Scope::root(graph)
  let source = Signal::new(scope, 1)
  let computes = Ref(0)
  let parity = Memo::new(scope, fn() {
    computes.val = computes.val + 1
    source.get() % 2
  })
  let applied : Array[Int] = []
  let _ = Binding::new(scope, fn() { parity.get() }, fn(value) {
    applied.push(value)
  })
  assert_eq(applied, [1])
  assert_eq(computes.val, 1)
  source.set(3)
  assert_eq(computes.val, 2)
  assert_eq(applied, [1])
  source.set(4)
  assert_eq(applied, [1, 0])
  source.set(4)
  assert_eq(computes.val, 3)
  scope.dispose()
}

///|
test "dynamic memo dependencies detach inactive branches" {
  let graph = Graph::new()
  let scope = Scope::root(graph)
  let choose_left = Signal::new(scope, true)
  let left = Signal::new(scope, 1)
  let right = Signal::new(scope, 2)
  let runs = Ref(0)
  let choice = Memo::new(scope, fn() {
    runs.val = runs.val + 1
    if choose_left.get() {
      left.get()
    } else {
      right.get()
    }
  })
  assert_eq(choice.get(), 1)
  choose_left.set(false)
  assert_eq(choice.get(), 2)
  left.set(3)
  assert_eq(choice.get(), 2)
  assert_eq(runs.val, 2)
  right.set(4)
  assert_eq(choice.get(), 4)
  assert_eq(runs.val, 3)
  scope.dispose()
}

///|
test "nested batch publishes a consistent diamond once" {
  let graph = Graph::new()
  let scope = Scope::root(graph)
  let source = Signal::new(scope, 1)
  let left = Memo::new(scope, fn() { source.get() + 1 })
  let right = Memo::new(scope, fn() { source.get() * 2 })
  let seen : Array[Int] = []
  let _ = Binding::new(scope, fn() { left.get() + right.get() }, fn(value) {
    seen.push(value)
  })
  graph.batch(fn() {
    source.set(2)
    graph.batch(fn() { source.set(3) })
  })
  assert_eq(seen, [4, 10])
  scope.dispose()
}

///|
test "untracked read does not subscribe" {
  let graph = Graph::new()
  let scope = Scope::root(graph)
  let tracked = Signal::new(scope, 1)
  let untracked = Signal::new(scope, 10)
  let runs = Ref(0)
  let _ = Effect::new(scope, fn(_) {
    let _ = tracked.get()
    let _ = graph.untracked(fn() { untracked.get() })
    runs.val = runs.val + 1
  })
  assert_eq(runs.val, 1)
  untracked.set(11)
  assert_eq(runs.val, 1)
  tracked.set(2)
  assert_eq(runs.val, 2)
  scope.dispose()
}

///|
test "child disposal runs cleanup once and prevents later updates" {
  let graph = Graph::new()
  let root = Scope::root(graph)
  let child = root.child()
  let source = Signal::new(root, 0)
  let events : Array[String] = []
  let _ = Effect::new(child, fn(effect) {
    let value = source.get()
    events.push("run:" + value.to_string())
    effect.on_cleanup(fn() { events.push("cleanup:" + value.to_string()) })
  })
  source.set(1)
  child.dispose()
  child.dispose()
  source.set(2)
  assert_eq(events, ["run:0", "cleanup:0", "run:1", "cleanup:1"])
  root.dispose()
}

///|
test "equal memo leaves downstream effect idle" {
  let graph = Graph::new()
  let scope = Scope::root(graph)
  let source = Signal::new(scope, 1)
  let parity = Memo::new(scope, fn() { source.get() % 2 })
  let runs = Ref(0)
  let _ = Effect::new(scope, fn(_) {
    let _ = parity.get()
    runs.val = runs.val + 1
  })
  source.set(3)
  assert_eq(runs.val, 1)
  source.set(4)
  assert_eq(runs.val, 2)
  scope.dispose()
}

///|
test "binding apply does not add a dependency" {
  let graph = Graph::new()
  let scope = Scope::root(graph)
  let source = Signal::new(scope, 1)
  let auxiliary = Signal::new(scope, 10)
  let applies = Ref(0)
  let _ = Binding::new(scope, fn() { source.get() }, fn(_) {
    let _ = auxiliary.get()
    applies.val = applies.val + 1
  })
  auxiliary.set(11)
  assert_eq(applies.val, 1)
  source.set(2)
  assert_eq(applies.val, 2)
  scope.dispose()
}

///|
test "cleanup disposal cannot rerun itself or the effect" {
  let graph = Graph::new()
  let scope = Scope::root(graph)
  let source = Signal::new(scope, 0)
  let events : Array[String] = []
  let _ = Effect::new(scope, fn(effect) {
    let value = source.get()
    events.push("run:" + value.to_string())
    effect.on_cleanup(fn() {
      events.push("cleanup")
      effect.dispose()
    })
  })
  source.set(1)
  source.set(2)
  assert_eq(events, ["run:0", "cleanup"])
  scope.dispose()
}

///|
test "effect cleanup reads do not subscribe the disposing effect" {
  let graph = Graph::new()
  let scope = Scope::root(graph)
  let dispose_target = Signal::new(scope, false)
  let cleanup_source = Signal::new(scope, 0)
  let target = Effect::new(scope, fn(effect) {
    effect.on_cleanup(fn() { let _ = cleanup_source.get() })
  })
  let runs = Ref(0)
  let _ = Effect::new(scope, fn(_) {
    if dispose_target.get() {
      target.dispose()
    }
    runs.val = runs.val + 1
  })
  dispose_target.set(true)
  cleanup_source.set(1)
  assert_eq(runs.val, 2)
  scope.dispose()
}

///|
test "scope cleanup reads do not subscribe the disposing effect" {
  let graph = Graph::new()
  let root = Scope::root(graph)
  let child = root.child()
  let dispose_child = Signal::new(root, false)
  let cleanup_source = Signal::new(root, 0)
  child.on_dispose(fn() { let _ = cleanup_source.get() })
  let runs = Ref(0)
  let _ = Effect::new(root, fn(_) {
    if dispose_child.get() {
      child.dispose()
    }
    runs.val = runs.val + 1
  })
  dispose_child.set(true)
  cleanup_source.set(1)
  assert_eq(runs.val, 2)
  root.dispose()
}

///|
test "memo read inside batch still publishes only final diamond value" {
  let graph = Graph::new()
  let scope = Scope::root(graph)
  let source = Signal::new(scope, 1)
  let left = Memo::new(scope, fn() { source.get() + 1 })
  let right = Memo::new(scope, fn() { source.get() * 2 })
  let seen : Array[Int] = []
  let _ = Binding::new(scope, fn() { left.get() + right.get() }, fn(value) {
    seen.push(value)
  })
  let intermediate = Ref(0)
  graph.batch(fn() {
    source.set(2)
    intermediate.val = left.get()
    source.set(3)
  })
  assert_eq(intermediate.val, 3)
  assert_eq(seen, [4, 10])
  scope.dispose()
}

///|
test "effect switches dependencies and ignores old branch" {
  let graph = Graph::new()
  let scope = Scope::root(graph)
  let choose_left = Signal::new(scope, true)
  let left = Signal::new(scope, 1)
  let right = Signal::new(scope, 2)
  let seen : Array[Int] = []
  let _ = Effect::new(scope, fn(_) {
    seen.push(if choose_left.get() { left.get() } else { right.get() })
  })
  choose_left.set(false)
  left.set(3)
  right.set(4)
  assert_eq(seen, [1, 2, 4])
  scope.dispose()
}

///|
test "scope disposal skips queued effects and runs child cleanup first" {
  let graph = Graph::new()
  let root = Scope::root(graph)
  let child = root.child()
  let source = Signal::new(root, 0)
  let events : Array[String] = []
  root.on_dispose(fn() { events.push("root") })
  child.on_dispose(fn() { events.push("child") })
  let _ = Effect::new(child, fn(effect) {
    let _ = source.get()
    events.push("run")
    effect.on_cleanup(fn() { events.push("cleanup") })
  })
  graph.batch(fn() {
    source.set(1)
    root.dispose()
  })
  assert_eq(events, ["run", "cleanup", "child", "root"])
}

///|
test "more than one thousand bindings share one source without a fixed queue" {
  let graph = Graph::new()
  let scope = Scope::root(graph)
  let source = Signal::new(scope, 0)
  let applies = Ref(0)
  for _ in 0..<1_025 {
    let _ = Binding::new(scope, fn() { source.get() }, fn(_) {
      applies.val = applies.val + 1
    })
  }
  assert_eq(applies.val, 1_025)
  source.set(1)
  assert_eq(applies.val, 2_050)
  scope.dispose()
}
