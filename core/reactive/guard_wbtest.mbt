///|
test "untracked evaluation still blocks writes" {
  let graph = Graph::new()
  let scope = Scope::root(graph)
  let source = Signal::new(scope, 0)
  let guarded = Ref(false)
  let memo = Memo::new(scope, fn() {
    let value = source.get()
    graph.untracked(fn() { guarded.val = write_guard_depth.val > 0 })
    value
  })
  assert_eq(memo.get(), 0)
  assert_eq(guarded.val, true)
  scope.dispose()
}
