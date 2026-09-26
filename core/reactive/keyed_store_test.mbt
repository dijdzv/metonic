///|
priv struct PublicItemRead {
  title : StoreRead[String]
}

///|
priv struct PublicItemWrite {
  title : StoreField[String]
}

///|
test "public keyed Store API keeps a removed writer from a recreated item" {
  let owner = Scope::root(Graph::new())
  let store = Store::new(owner)
  let orders : KeyedStore[String, PublicItemRead, PublicItemWrite] = store.keyed()
  let old = orders
    .insert("WO-1", builder => {
      let title = builder.field("First")
      ({ title: title.read(), }, { title, })
    })
    .unwrap()
  let visible = orders.read()
  let old_read = visible.lookup("WO-1").unwrap()
  assert_eq(old_read.fields().unwrap().title.get(), "First")
  assert_eq(orders.remove("WO-1"), Ok(()))
  let replacement = orders
    .insert("WO-1", builder => {
      let title = builder.field("Second")
      ({ title: title.read(), }, { title, })
    })
    .unwrap()
  assert_true(old.fields() is Err(StaleItem))
  assert_true(old_read.fields() is Err(StaleItem))
  replacement.fields().unwrap().title.set("Updated")
  assert_eq(
    visible.lookup("WO-1").unwrap().fields().unwrap().title.get(),
    "Updated",
  )
  owner.dispose()
}
