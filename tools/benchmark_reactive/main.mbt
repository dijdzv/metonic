///|
fn run_signal_updates(count : Int, offset : Int) -> (Int, Int) {
  let graph = @reactive.Graph::new()
  let scope = @reactive.Scope::root(graph)
  let source = @reactive.Signal::new(scope, 0)
  let value = @reactive.Memo::new(scope, fn() { source.get() * 2 })
  let observed = Ref(0)
  let notifications = Ref(0)
  let _ = @reactive.Binding::new(scope, fn() { value.get() }, fn(next) {
    observed.val = next
    notifications.val += 1
  })
  let started = @async.now()
  for i in 0..<count {
    source.set(offset + i + 1)
  }
  let elapsed = (@async.now() - started).to_int()
  let check = observed.val + notifications.val
  scope.dispose()
  (elapsed, check)
}

///|
fn main {
  let count = 100000
  let _ = run_signal_updates(count, 0)
  for trial in 0..<3 {
    let (reactive_ms, reactive_check) = run_signal_updates(count, trial * count)
    println(
      "trial=" +
      trial.to_string() +
      " count=" +
      count.to_string() +
      " reactive_ms=" +
      reactive_ms.to_string() +
      " check=" +
      reactive_check.to_string(),
    )
  }
}
