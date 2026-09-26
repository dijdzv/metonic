///|
priv struct WorkOrderFields {
  title : StoreField[String]
  details : StoreField[String]
  closed : StoreField[Bool]
}

///|
fn work_order_fields(store : Store) -> WorkOrderFields {
  {
    title: store.field("Inspect entry light"),
    details: store.field("Check the switch and lamp."),
    closed: store.field(false),
  }
}

///|
test "store fields track only the fields a reader uses" {
  let graph = Graph::new()
  let root = Scope::root(graph)
  let document = root.child()
  let order = work_order_fields(Store::new(document))
  let title = order.title.read()
  let details = order.details.read()
  let closed = order.closed.read()
  let title_evaluations = Ref(0)
  let details_evaluations = Ref(0)
  let title_view = Memo::new(document, () => {
    title_evaluations.val += 1
    title.get()
  })
  let details_view = Memo::new(document, () => {
    details_evaluations.val += 1
    details.get()
  })
  assert_eq(title_view.get(), "Inspect entry light")
  assert_eq(details_view.get(), "Check the switch and lamp.")
  order.details.set("Replace the lamp.")
  assert_eq(title_view.get(), "Inspect entry light")
  assert_eq(details_view.get(), "Replace the lamp.")
  assert_eq(title_evaluations.val, 1)
  assert_eq(details_evaluations.val, 2)
  assert_false(closed.peek())
  document.dispose()
  root.dispose()
}

///|
test "store batch publishes only the final structured state" {
  let graph = Graph::new()
  let root = Scope::root(graph)
  let store = Store::new(root)
  let order = work_order_fields(store)
  let title = order.title.read()
  let closed = order.closed.read()
  let seen : Array[String] = []
  let _ = Binding::new(
    root,
    () => title.get() + ":" + closed.get().to_string(),
    value => seen.push(value),
  )
  store.batch(() => {
    order.title.set("Replace room filter")
    store.batch(() => order.closed.set(true))
  })
  assert_eq(seen, ["Inspect entry light:false", "Replace room filter:true"])
  root.dispose()
}

///|
test "store fields honor an explicit equality policy" {
  let root = Scope::root(Graph::new())
  let store = Store::new(root)
  let parity = store.field_by(1, (left, right) => left % 2 == right % 2)
  let reader = parity.read()
  let seen : Array[Int] = []
  let _ = Binding::new(root, () => reader.get(), value => seen.push(value))
  parity.update(value => value + 2)
  assert_eq(reader.peek(), 1)
  assert_eq(seen, [1])
  parity.set(2)
  assert_eq(reader.peek(), 2)
  assert_eq(seen, [1, 2])
  root.dispose()
}

///|
test "store owners and their subscriptions are isolated by scope and graph" {
  let first_root = Scope::root(Graph::new())
  let second_root = Scope::root(Graph::new())
  let first_document = first_root.child()
  let first_component = first_document.child()
  let first = Store::new(first_document).field("first")
  let component_field = Store::new(first_component).field("local")
  let second = Store::new(second_root).field("second")
  let first_reader = first.read()
  let local_reader = component_field.read()
  let second_reader = second.read()
  let first_seen : Array[String] = []
  let local_seen : Array[String] = []
  let second_seen : Array[String] = []
  let _ = Binding::new(first_document, () => first_reader.get(), value => {
    first_seen.push(value)
  })
  let _ = Binding::new(second_root, () => second_reader.get(), value => {
    second_seen.push(value)
  })
  let _ = Binding::new(first_component, () => local_reader.get(), value => {
    local_seen.push(value)
  })
  first.set("updated")
  assert_eq(first_seen, ["first", "updated"])
  assert_eq(local_seen, ["local"])
  assert_eq(second_seen, ["second"])
  first_component.dispose()
  first_document.dispose()
  second.set("also updated")
  assert_eq(first_seen, ["first", "updated"])
  assert_eq(local_seen, ["local"])
  assert_eq(second_seen, ["second", "also updated"])
  first_root.dispose()
  second_root.dispose()
}
