///|
fn published_ready(
  source_id : Int,
  cycle : Cycle,
  revision : Int,
  value : Int,
) -> Current[Int] {
  let origin : Origin = {
    source_id,
    admission_id: source_id * 100,
    revision,
    cycle,
  }
  {
    evidence: {
      observations: [{ source_id, origin: Some(origin), phase: LeafReady, }],
      related_mismatch: false,
    },
    value: Some(value),
  }
}

///|
test "a publication round commits two sampled displays atomically" {
  let graph = @reactive.Graph::new()
  let root = @reactive.Scope::root(graph)
  let registry = PublicationRegistry::new(root)
  let cycle = Cycle::new()
  let first = @reactive.Signal::new(root, 1)
  let second = @reactive.Signal::new(root, 10)
  let first_view = registry.register(root, () => {
    let value = first.get()
    ("same", published_ready(51, cycle, value, value))
  })
  let second_view = registry.register(root, () => {
    let value = second.get()
    ("same", published_ready(52, cycle, value, value))
  })
  let seen : Array[(Published[String, Int]?, Published[String, Int]?)] = []
  let _ = @reactive.Binding::new(
    root,
    () => (first_view.get(), second_view.get()),
    values => seen.push(values),
  )
  assert_eq(seen.length(), 1)
  assert_eq(seen[0], (None, None))
  assert_true(registry.publish())
  assert_eq(seen.length(), 2)
  match seen[1] {
    (Some(a), Some(b)) => {
      assert_true(a.current is CurrentReady(1, _))
      assert_true(b.current is CurrentReady(10, _))
    }
    _ => fail("both publications must appear in one binding round")
  }
  assert_false(registry.publish())
  assert_eq(seen.length(), 2)
  graph.batch(() => {
    first.set(2)
    second.set(20)
  })
  assert_eq(seen.length(), 2)
  assert_true(registry.publish())
  assert_eq(seen.length(), 3)
  match seen[2] {
    (Some(a), Some(b)) => {
      assert_true(a.current is CurrentReady(2, _))
      assert_true(b.current is CurrentReady(20, _))
    }
    _ => fail("the observer saw a half-committed publication")
  }
  root.dispose()
}

///|
test "disposing an owner unregisters its publication before the next round" {
  let graph = @reactive.Graph::new()
  let root = @reactive.Scope::root(graph)
  let child = root.child()
  let registry = PublicationRegistry::new(root)
  let cycle = Cycle::new()
  let samples = Ref(0)
  let _ = registry.register(child, () => {
    samples.val += 1
    ("one", published_ready(61, cycle, 1, 4))
  })
  assert_true(registry.publish())
  assert_eq(samples.val, 1)
  assert_eq(registry.entries.length(), 1)
  child.dispose()
  assert_eq(registry.entries.length(), 0)
  assert_false(registry.publish())
  assert_eq(samples.val, 1)
  root.dispose()
}
