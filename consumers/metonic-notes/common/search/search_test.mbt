///|
fn document() -> @collection.Document {
  let (first, id) = @collection.empty().create_note().unwrap()
  let first = first.edit(id, "Alpha 日本語").unwrap()
  let (second, id) = first.create_note().unwrap()
  second.edit(id, "Beta").unwrap()
}

///|
async test "reactive search publishes changed rows and suppresses equal results" {
  let scope = @reactive.Scope::root(@reactive.Graph::new())
  let model = @search.create(scope, _ => ())
  let observed : Array[Array[Int]] = []
  let _ = @reactive.Binding::new(
    scope,
    () => model.items().map(note => note.id),
    ids => observed.push(ids.copy()),
  )
  model.refresh(document())
  let first = model.request("alpha", () => ()).unwrap()
  first.invalidate()
  assert_eq(first.prepare().unwrap().run().apply(), @task.Changed)
  let same = model.request("alpha", () => ()).unwrap()
  same.invalidate()
  assert_eq(same.prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(observed, [[], [1, 2], [1]])
  scope.dispose()
}

///|
async test "Scope disposal rejects a prepared search completion" {
  let scope = @reactive.Scope::root(@reactive.Graph::new())
  let model = @search.create(scope, _ => ())
  model.refresh(document())
  let request = model.request("alpha", () => ()).unwrap()
  request.invalidate()
  let completion = request.prepare().unwrap().run()
  scope.dispose()
  assert_eq(completion.apply(), @task.Rejected)
  model.close()
}

///|
async test "query replacement rejects earlier results and clear restores all notes" {
  let model = @search.create(@reactive.Scope::root(@reactive.Graph::new()), _ => ())
  model.refresh(document())
  let first = model.request("alpha", () => ()).unwrap()
  first.invalidate()
  let earlier = first.prepare().unwrap().run()
  let second = model.request("BETA", () => ()).unwrap()
  second.invalidate()
  assert_eq(second.prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(earlier.apply(), @task.Rejected)
  assert_eq(model.items().map(note => note.id), [2])
  ignore(model.request("", () => ()))
  assert_eq(model.items().length(), 2)
}

///|
async test "collection changes and close reject stale search results" {
  let model = @search.create(@reactive.Scope::root(@reactive.Graph::new()), _ => ())
  let original = document()
  model.refresh(original)
  let request = model.request("日本語", () => ()).unwrap()
  request.invalidate()
  let completion = request.prepare().unwrap().run()
  model.refresh(original.remove(1).unwrap())
  assert_eq(completion.apply(), @task.Rejected)
  assert_eq(model.items().length(), 0)
  let request = model.request("beta", () => ()).unwrap()
  request.invalidate()
  let completion = request.prepare().unwrap().run()
  model.close()
  assert_eq(completion.apply(), @task.Rejected)
  assert_eq(model.items().length(), 0)
  assert_true(model.request("", () => ()) is None)
}

///|
async test "search results follow reordered documents and remain owned by the model" {
  let model = @search.create(@reactive.Scope::root(@reactive.Graph::new()), _ => ())
  let original = document()
  model.refresh(original)
  let returned = model.items()
  returned.clear()
  assert_eq(model.items().map(note => note.id), [1, 2])
  model.refresh(original.reorder(2, @collection.MoveDirection::Up).unwrap())
  assert_eq(model.items().map(note => note.id), [2, 1])
  let request = model.request("alpha", () => ()).unwrap()
  request.invalidate()
  assert_eq(request.prepare().unwrap().run().apply(), @task.Changed)
  assert_eq(model.items().map(note => note.id), [1])
}
