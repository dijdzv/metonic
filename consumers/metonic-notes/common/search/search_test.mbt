///|
fn document() -> @collection.Document {
  let (first, id) = @collection.empty().create_note().unwrap()
  let first = first.edit(id, "Alpha 日本語").unwrap()
  let (second, id) = first.create_note().unwrap()
  second.edit(id, "Beta").unwrap()
}

///|
async test "query replacement rejects earlier results and clear restores all notes" {
  let model = @search.create(_ => ())
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
  let model = @search.create(_ => ())
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
  let model = @search.create(_ => ())
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
