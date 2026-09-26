///|
struct OrderIdentity {
  id : String
  generation : Int
} derive(Eq, Hash, Debug)

///|
priv struct OrderFieldsRead {
  title : @reactive.StoreRead[String]
  details : @reactive.StoreRead[String]
  closed : @reactive.StoreRead[Bool]
}

///|
priv struct OrderFieldsWrite {
  title : @reactive.StoreField[String]
  details : @reactive.StoreField[String]
}

///|
priv struct OrderModel {
  store : @reactive.Store
  items : @reactive.KeyedStore[String, OrderFieldsRead, OrderFieldsWrite]
}

///|
fn OrderModel::new(scope : @reactive.Scope) -> OrderModel {
  let store = @reactive.Store::new(scope)
  { store, items: store.keyed(), }
}

///|
fn OrderModel::read(
  self : OrderModel,
) -> @reactive.KeyedStoreRead[String, OrderFieldsRead, OrderFieldsWrite] {
  self.items.read()
}

///|
fn OrderModel::insert(self : OrderModel, order : WorkOrder) -> Unit {
  ignore(
    self.items
    .insert(order.id, builder => {
      let title = builder.field(order.title)
      let details = builder.field(order.details)
      let closed = builder.field(order.closed)
      (
        { title: title.read(), details: details.read(), closed: closed.read(), },
        { title, details, },
      )
    })
    .unwrap(),
  )
}

///|
fn OrderModel::replace_all(
  self : OrderModel,
  loaded : Array[WorkOrder],
) -> Unit {
  self.store.batch(() => {
    for id in self.items.read().keys() {
      ignore(self.items.remove(id).unwrap())
    }
    for order in loaded {
      self.insert(order)
    }
  })
}

///|
fn OrderModel::identity(self : OrderModel, id : String) -> OrderIdentity? {
  self.items
  .read()
  .lookup(id)
  .map(item => { id, generation: item.generation(), })
}

///|
fn OrderModel::snapshot(self : OrderModel) -> Array[WorkOrder] {
  let read = self.read()
  read
  .keys()
  .map(id => {
    let fields = read.lookup(id).unwrap().fields().unwrap()
    {
      id,
      title: fields.title.peek(),
      details: fields.details.peek(),
      closed: fields.closed.peek(),
    }
  })
}

///|
fn OrderModel::edit(
  self : OrderModel,
  identity : OrderIdentity,
  value : String,
  title : Bool,
) -> Bool {
  guard self.items.get_mut(identity.id) is Some(item) &&
    item.read().generation() == identity.generation &&
    item.fields() is Ok(fields) else {
    return false
  }
  if title {
    if fields.title.read().peek() == value {
      return false
    }
    fields.title.set(value)
  } else {
    if fields.details.read().peek() == value {
      return false
    }
    fields.details.set(value)
  }
  true
}

///|
fn selected_fields(
  read : @reactive.KeyedStoreRead[String, OrderFieldsRead, OrderFieldsWrite],
  selected : @reactive.Signal[OrderIdentity?],
) -> OrderFieldsRead? {
  guard selected.get() is Some(identity) &&
    read.lookup(identity.id) is Some(item) &&
    item.generation() == identity.generation &&
    item.fields() is Ok(fields) else {
    return None
  }
  Some(fields)
}

///|
fn visible_rows(
  read : @reactive.KeyedStoreRead[String, OrderFieldsRead, OrderFieldsWrite],
  query : @reactive.StoreRead[String],
  show_closed : @reactive.StoreRead[Bool],
) -> Array[@component.ListRow[OrderIdentity]] {
  let search = query.get()
  let include_closed = show_closed.get()
  let rows : Array[@component.ListRow[OrderIdentity]] = []
  for id in read.keys() {
    let item = read.lookup(id).unwrap()
    let fields = item.fields().unwrap()
    let title = fields.title.get()
    let closed = fields.closed.get()
    if (include_closed || !closed) &&
      (search == "" || id.contains(search) || title.contains(search)) {
      rows.push({
        key: { id, generation: item.generation(), },
        label: id + "  " + title,
        enabled: true,
      })
    }
  }
  rows
}
