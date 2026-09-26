///|
priv struct KeyedTestRead {
  title : StoreRead[String]
  details : StoreRead[String]
}

///|
priv struct KeyedTestWrite {
  title : StoreField[String]
  details : StoreField[String]
}

///|
fn make_keyed_test_item(
  builder : StoreItemBuilder,
  title : String,
) -> (KeyedTestRead, KeyedTestWrite) {
  let title_field = builder.field(title)
  let details_field = builder.field("")
  (
    { title: title_field.read(), details: details_field.read(), },
    { title: title_field, details: details_field, },
  )
}

///|
test "keyed Store tracks order, membership and item fields independently" {
  let root = Scope::root(Graph::new())
  let document = root.child()
  let store = Store::new(document)
  let items : KeyedStore[String, KeyedTestRead, KeyedTestWrite] = store.keyed()
  let first = items
    .insert("a", builder => make_keyed_test_item(builder, "A"))
    .unwrap()
  let second = items
    .insert("b", builder => make_keyed_test_item(builder, "B"))
    .unwrap()
  let read = items.read()
  let order_runs = Ref(0)
  let title_runs = Ref(0)
  let details_runs = Ref(0)
  let other_runs = Ref(0)
  let order = Memo::new(document, () => {
    order_runs.val += 1
    read.keys()
  })
  let title = Memo::new(document, () => {
    title_runs.val += 1
    read.lookup("a").unwrap().fields().unwrap().title.get()
  })
  let details = Memo::new(document, () => {
    details_runs.val += 1
    read.lookup("a").unwrap().fields().unwrap().details.get()
  })
  let other = Memo::new(document, () => {
    other_runs.val += 1
    read.lookup("b").unwrap().fields().unwrap().title.get()
  })
  assert_eq(order.get(), ["a", "b"])
  assert_eq(title.get(), "A")
  assert_eq(details.get(), "")
  assert_eq(other.get(), "B")
  first.fields().unwrap().details.set("A details")
  assert_eq(details.get(), "A details")
  assert_eq(title.get(), "A")
  assert_eq(other.get(), "B")
  assert_eq(order.get(), ["a", "b"])
  assert_eq(
    (order_runs.val, title_runs.val, details_runs.val, other_runs.val),
    (1, 1, 2, 1),
  )
  let first_generation = first.read().generation()
  assert_eq(items.reorder(["b", "a"]), Ok(()))
  assert_eq(order.get(), ["b", "a"])
  assert_eq(title.get(), "A")
  assert_eq(other.get(), "B")
  assert_eq((order_runs.val, title_runs.val, other_runs.val), (2, 1, 1))
  assert_eq(read.lookup("a").unwrap().generation(), first_generation)
  second.fields().unwrap().title.set("B changed")
  assert_eq(other.get(), "B changed")
  assert_eq(title.get(), "A")
  assert_eq(title_runs.val, 1)
  root.dispose()
}

///|
test "keyed Store rejects stale generations after remove and recreate in one batch" {
  let root = Scope::root(Graph::new())
  let store = Store::new(root)
  let items : KeyedStore[String, KeyedTestRead, KeyedTestWrite] = store.keyed()
  let old = items
    .insert("a", builder => make_keyed_test_item(builder, "Old"))
    .unwrap()
  let retired_signal = old.fields().unwrap().title.value
  let read = items.read()
  let old_reader = read.lookup("a").unwrap()
  let seen : Array[String] = []
  let _ = Binding::new(
    root,
    () => {
      match read.lookup("a") {
        Some(item) => item.fields().unwrap().title.get()
        None => "missing"
      }
    },
    value => seen.push(value),
  )
  let stale_in_batch = Ref(false)
  store.batch(() => {
    ignore(items.remove("a"))
    stale_in_batch.val = old_reader.fields() is Err(StaleItem) &&
      old.fields() is Err(StaleItem)
    ignore(items.insert("a", builder => make_keyed_test_item(builder, "New")))
  })
  assert_true(stale_in_batch.val)
  let replacement = read.lookup("a").unwrap()
  assert_true(replacement.generation() != old_reader.generation())
  assert_eq(replacement.fields().unwrap().title.get(), "New")
  assert_eq(seen, ["Old", "New"])
  assert_false(old.entry.live)
  assert_true(old.entry.reader is None)
  assert_true(old.entry.writer is None)
  assert_true(old.entry.builder is None)
  assert_true(retired_signal.node.disposed)
  assert_eq(retired_signal.node.observers.length(), 0)
  root.dispose()
}

///|
test "keyed Store validates structural edits before publishing" {
  let root = Scope::root(Graph::new())
  let items : KeyedStore[String, KeyedTestRead, KeyedTestWrite] = Store::new(
    root,
  ).keyed()
  ignore(items.insert("a", builder => make_keyed_test_item(builder, "A")))
  ignore(items.insert("b", builder => make_keyed_test_item(builder, "B")))
  let read = items.read()
  let generation = read.lookup("a").unwrap().generation()
  assert_true(
    items.insert("a", builder => make_keyed_test_item(builder, "Wrong"))
    is Err(DuplicateKey),
  )
  assert_true(items.reorder(["a", "a"]) is Err(InvalidOrder))
  assert_true(items.reorder(["a", "missing"]) is Err(InvalidOrder))
  assert_true(items.reorder(["b"]) is Err(InvalidOrder))
  assert_true(items.remove("missing") is Err(MissingKey))
  assert_eq(read.keys(), ["a", "b"])
  assert_eq(read.lookup("a").unwrap().generation(), generation)
  assert_eq(read.lookup("a").unwrap().fields().unwrap().title.get(), "A")
  let detached = read.keys()
  detached.clear()
  assert_eq(read.keys(), ["a", "b"])
  root.dispose()
}

///|
test "keyed Store releases removed registrations and isolates application graphs" {
  let first_root = Scope::root(Graph::new())
  let second_root = Scope::root(Graph::new())
  let first_store = Store::new(first_root)
  let first : KeyedStore[String, KeyedTestRead, KeyedTestWrite] = first_store.keyed()
  let second : KeyedStore[String, KeyedTestRead, KeyedTestWrite] = Store::new(
    second_root,
  ).keyed()
  let registration_count = first_root.disposers.length()
  ignore(
    second.insert("a", builder => make_keyed_test_item(builder, "Other app")),
  )
  let second_read = second.read()
  let other_runs = Ref(0)
  let other = Memo::new(second_root, () => {
    other_runs.val += 1
    second_read.lookup("a").unwrap().fields().unwrap().title.get()
  })
  assert_eq(other.get(), "Other app")
  for _ in 0..<200 {
    let old = first
      .insert("a", builder => make_keyed_test_item(builder, "Temporary"))
      .unwrap()
    let old_read = old.read()
    let removed_signal = old.fields().unwrap().title.value
    assert_eq(first.remove("a"), Ok(()))
    assert_true(old.fields() is Err(StaleItem))
    assert_true(old_read.fields() is Err(StaleItem))
    assert_eq(first.entries.length(), 0)
    assert_eq(first_root.disposers.length(), registration_count)
    assert_eq(first_root.children.length(), 0)
    assert_eq(first_root.graph().pending.length(), 0)
    assert_eq(first.read().keys(), [])
    assert_true(removed_signal.node.disposed)
  }
  assert_eq(other.get(), "Other app")
  assert_eq(other_runs.val, 1)
  let retained = second_read.lookup("a").unwrap()
  first_root.dispose()
  second_root.dispose()
  assert_true(retained.fields() is Err(StaleItem))
}

///|
test "keyed Store refuses structural reentry during item construction" {
  let root = Scope::root(Graph::new())
  let items : KeyedStore[String, KeyedTestRead, KeyedTestWrite] = Store::new(
    root,
  ).keyed()
  ignore(items.insert("b", builder => make_keyed_test_item(builder, "B")))
  let nested_insert = Ref(false)
  let nested_remove = Ref(false)
  let nested_reorder = Ref(false)
  let created = items.insert("a", builder => {
    nested_insert.val = items.insert("a", inner => {
        make_keyed_test_item(inner, "Wrong")
      })
      is Err(ReentrantEdit)
    nested_remove.val = items.remove("b") is Err(ReentrantEdit)
    nested_reorder.val = items.reorder(["b"]) is Err(ReentrantEdit)
    make_keyed_test_item(builder, "A")
  })
  assert_true(created is Ok(_))
  assert_true(nested_insert.val && nested_remove.val && nested_reorder.val)
  assert_eq(items.read().keys(), ["b", "a"])
  assert_eq(items.entries.length(), 2)
  assert_eq(
    items.read().lookup("b").unwrap().fields().unwrap().title.get(),
    "B",
  )
  root.dispose()
}

///|
test "keyed Store releases a partially built item if its owner closes" {
  let root = Scope::root(Graph::new())
  let items : KeyedStore[String, KeyedTestRead, KeyedTestWrite] = Store::new(
    root,
  ).keyed()
  let temporary : Ref[StoreField[String]?] = Ref(None)
  let created = items.insert("a", builder => {
    let title = builder.field("Transient")
    temporary.val = Some(title)
    root.dispose()
    (
      { title: title.read(), details: title.read(), },
      { title, details: title, },
    )
  })
  assert_true(created is Err(ClosedStore))
  assert_eq(items.entries.length(), 0)
  assert_true(temporary.val.unwrap().value.node.disposed)
}

///|
test "retained keyed reader invalidates derived reactions when its item is removed" {
  let root = Scope::root(Graph::new())
  let items : KeyedStore[String, String, Unit] = Store::new(root).keyed()
  ignore(items.insert("a", _ => ("constant projection", ())))
  let retained = items.read().lookup("a").unwrap()
  let direct_runs = Ref(0)
  let downstream_runs = Ref(0)
  let direct = Memo::new(root, () => {
    direct_runs.val += 1
    match retained.fields() {
      Ok(value) => value
      Err(StaleItem) => "stale"
      Err(_) => "other error"
    }
  })
  let downstream = Memo::new(root, () => {
    downstream_runs.val += 1
    direct.get() + "!"
  })
  let seen : Array[String] = []
  let _ = Binding::new(root, () => downstream.get(), value => seen.push(value))
  assert_eq(seen, ["constant projection!"])
  assert_eq(items.remove("a"), Ok(()))
  assert_eq(seen, ["constant projection!", "stale!"])
  assert_eq((direct_runs.val, downstream_runs.val), (2, 2))
  root.dispose()
}

///|
test "keyed Store releases fields omitted from the public item projection" {
  let root = Scope::root(Graph::new())
  let items : KeyedStore[String, String, Unit] = Store::new(root).keyed()
  let hidden : Ref[StoreField[String]?] = Ref(None)
  ignore(
    items.insert("a", builder => {
      hidden.val = Some(builder.field("hidden"))
      ("visible", ())
    }),
  )
  assert_eq(items.remove("a"), Ok(()))
  assert_true(hidden.val.unwrap().value.node.disposed)
  root.dispose()
}
