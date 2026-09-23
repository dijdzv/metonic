///|
fn main {
  let args = @env.args()
  if args.length() == 0 {
    abort("provide one reactive negative case")
  }
  let graph = @reactive.Graph::new()
  let root = @reactive.Scope::root(graph)
  match args[args.length() - 1] {
    "cycle" => {
      let holder : Ref[@reactive.Memo[Int]?] = Ref(None)
      let memo = @reactive.Memo::new(root, fn() {
        match holder.val {
          Some(current) => current.get()
          None => 0
        }
      })
      holder.val = Some(memo)
      let _ = memo.get()
    }
    "untracked-write" => {
      let source = @reactive.Signal::new(root, 0)
      let memo = @reactive.Memo::new(root, fn() {
        let value = source.get()
        graph.untracked(fn() { source.set(value + 1) })
        value
      })
      let _ = memo.get()
    }
    "cross-graph" => {
      let other_graph = @reactive.Graph::new()
      let other_root = @reactive.Scope::root(other_graph)
      let source = @reactive.Signal::new(other_root, 0)
      let _ = @reactive.Effect::new(root, fn(_) { let _ = source.get() })
    }
    "short-scope" => {
      let child = root.child()
      let source = @reactive.Signal::new(child, 0)
      let _ = @reactive.Effect::new(root, fn(_) { let _ = source.get() })
    }
    "disposed-owner" => {
      root.dispose()
      let _ = @reactive.Effect::new(root, fn(_) { () })
    }
    "scope-cleanup-write" => {
      let source = @reactive.Signal::new(root, 0)
      let child = root.child()
      child.on_dispose(fn() { source.set(1) })
      child.dispose()
    }
    "update-reentry" => {
      let source = @reactive.Signal::new(root, 0)
      source.update(fn(value) {
        source.set(value + 1)
        value + 2
      })
    }
    _ => abort("unknown reactive negative case")
  }
  abort("reactive negative case was accepted")
}
