///|
pub enum KeyedStoreError {
  DuplicateKey
  MissingKey
  InvalidOrder
  StaleItem
  ClosedStore
  GenerationExhausted
  ReentrantEdit
} derive(Eq, Debug)

///|
pub struct StoreItemBuilder {
  priv scope : Scope
  priv disposers : Array[() -> Unit]
  priv mut creating : Bool
  priv mut live : Bool
}

///|
fn StoreItemBuilder::new(scope : Scope) -> StoreItemBuilder {
  { scope, disposers: [], creating: true, live: true, }
}

///|
pub fn[T : Eq] StoreItemBuilder::field(
  self : StoreItemBuilder,
  initial : T,
) -> StoreField[T] {
  self.field_by(initial, (left, right) => left == right)
}

///|
pub fn[T] StoreItemBuilder::field_by(
  self : StoreItemBuilder,
  initial : T,
  equal : (T, T) -> Bool,
) -> StoreField[T] {
  if !self.creating || !self.live {
    abort("keyed Store item fields can only be created during insertion")
  }
  // Do not register each item node on the document Scope: repeated removal
  // would retain one cleanup closure per retired item until document disposal.
  let signal = Signal::new_unowned_by(self.scope, initial, equal)
  self.disposers.push(() => signal.node.dispose())
  { value: signal, }
}

///|
fn StoreItemBuilder::finish(self : StoreItemBuilder) -> Unit {
  self.creating = false
}

///|
fn StoreItemBuilder::dispose(self : StoreItemBuilder) -> Unit {
  if !self.live {
    return
  }
  self.live = false
  for i = self.disposers.length() - 1; i >= 0; i = i - 1 {
    self.disposers[i]()
  }
  self.disposers.clear()
}

///|
priv struct KeyedEntry[K, R, W] {
  key : K
  generation : Int
  mut reader : R?
  mut writer : W?
  mut builder : StoreItemBuilder?
  mut liveness : Signal[Bool]?
  mut live : Bool
}

///|
fn[K, R, W] KeyedEntry::retire(
  self : KeyedEntry[K, R, W],
  notify : Bool,
) -> Unit {
  if !self.live {
    return
  }
  if notify && self.liveness is Some(liveness) {
    liveness.set(false)
  }
  self.live = false
  self.reader = None
  self.writer = None
  self.liveness = None
  if self.builder is Some(builder) {
    builder.dispose()
    self.builder = None
  }
}

///|
pub struct KeyedStore[K, R, W] {
  priv owner : Scope
  priv entries : Map[K, KeyedEntry[K, R, W]]
  priv order : StoreField[Array[K]]
  priv membership : StoreField[Int]
  priv mut next_generation : Int
  priv mut live : Bool
  priv mut constructing : Bool
}

///|
pub struct KeyedStoreRead[K, R, W] {
  priv store : KeyedStore[K, R, W]
}

///|
pub struct KeyedItemRead[K, R, W] {
  priv entry : KeyedEntry[K, R, W]
}

///|
pub struct KeyedItemWrite[K, R, W] {
  priv entry : KeyedEntry[K, R, W]
}

///|
pub fn[K : Eq + Hash, R, W] Store::keyed(self : Store) -> KeyedStore[K, R, W] {
  self.owner.assert_alive()
  let items : KeyedStore[K, R, W] = {
    owner: self.owner,
    entries: Map([]),
    order: self.field([]),
    membership: self.field(0),
    next_generation: 0,
    live: true,
    constructing: false,
  }
  self.owner.on_dispose(() => items.retire())
  items
}

///|
fn[K, R, W] KeyedStore::retire(self : KeyedStore[K, R, W]) -> Unit {
  if !self.live {
    return
  }
  self.live = false
  for _, entry in self.entries {
    entry.retire(false)
  }
  self.entries.clear()
}

///|
pub fn[K, R, W] KeyedStore::read(
  self : KeyedStore[K, R, W],
) -> KeyedStoreRead[K, R, W] {
  { store: self, }
}

///|
pub fn[K : Eq + Hash, R, W] KeyedStore::insert(
  self : KeyedStore[K, R, W],
  key : K,
  make : (StoreItemBuilder) -> (R, W),
) -> Result[KeyedItemWrite[K, R, W], KeyedStoreError] {
  guard self.live else { return Err(ClosedStore) }
  guard !self.constructing else { return Err(ReentrantEdit) }
  guard !self.entries.contains(key) else { return Err(DuplicateKey) }
  guard self.next_generation < 0x7fffffff else {
    return Err(GenerationExhausted)
  }
  self.owner.graph().assert_can_write()
  self.constructing = true
  defer {
    self.constructing = false
  }
  let builder = StoreItemBuilder::new(self.owner)
  let liveness = builder.field(true).value
  let (reader, writer) = make(builder)
  builder.finish()
  guard self.live && !self.owner.is_disposed() else {
    builder.dispose()
    return Err(ClosedStore)
  }
  let generation = self.next_generation + 1
  let entry : KeyedEntry[K, R, W] = {
    key,
    generation,
    reader: Some(reader),
    writer: Some(writer),
    builder: Some(builder),
    liveness: Some(liveness),
    live: true,
  }
  self.owner
  .graph()
  .batch(() => {
    self.next_generation = generation
    self.entries[key] = entry
    let next = self.order.read().peek().copy()
    next.push(key)
    self.order.set(next)
    self.membership.set(generation)
  })
  Ok({ entry, })
}

///|
pub fn[K : Eq + Hash, R, W] KeyedStore::remove(
  self : KeyedStore[K, R, W],
  key : K,
) -> Result[Unit, KeyedStoreError] {
  guard self.live else { return Err(ClosedStore) }
  guard !self.constructing else { return Err(ReentrantEdit) }
  guard self.entries.get(key) is Some(entry) else { return Err(MissingKey) }
  guard self.next_generation < 0x7fffffff else {
    return Err(GenerationExhausted)
  }
  self.owner.graph().assert_can_write()
  self.owner
  .graph()
  .batch(() => {
    self.next_generation += 1
    self.entries.remove(key)
    self.order.set(self.order.read().peek().filter(value => value != key))
    self.membership.set(self.next_generation)
    entry.retire(true)
  })
  Ok(())
}

///|
pub fn[K : Eq + Hash, R, W] KeyedStore::reorder(
  self : KeyedStore[K, R, W],
  keys : Array[K],
) -> Result[Unit, KeyedStoreError] {
  guard self.live else { return Err(ClosedStore) }
  guard !self.constructing else { return Err(ReentrantEdit) }
  guard keys.length() == self.entries.length() else { return Err(InvalidOrder) }
  let seen : Set[K] = Set([])
  for key in keys {
    guard self.entries.contains(key) && !seen.contains(key) else {
      return Err(InvalidOrder)
    }
    seen.add(key)
  }
  self.owner.graph().assert_can_write()
  self.order.set(keys.copy())
  Ok(())
}

///|
pub fn[K : Eq + Hash, R, W] KeyedStore::get_mut(
  self : KeyedStore[K, R, W],
  key : K,
) -> KeyedItemWrite[K, R, W]? {
  guard self.live else { return None }
  self.entries.get(key).map(entry => { entry, })
}

///|
pub fn[K, R, W] KeyedStoreRead::keys(
  self : KeyedStoreRead[K, R, W],
) -> Array[K] {
  self.store.order.read().get().copy()
}

///|
pub fn[K : Eq + Hash, R, W] KeyedStoreRead::lookup(
  self : KeyedStoreRead[K, R, W],
  key : K,
) -> KeyedItemRead[K, R, W]? {
  ignore(self.store.membership.read().get())
  self.store.entries.get(key).map(entry => { entry, })
}

///|
pub fn[K, R, W] KeyedItemRead::key(self : KeyedItemRead[K, R, W]) -> K {
  self.entry.key
}

///|
pub fn[K, R, W] KeyedItemRead::generation(self : KeyedItemRead[K, R, W]) -> Int {
  self.entry.generation
}

///|
pub fn[K, R, W] KeyedItemRead::fields(
  self : KeyedItemRead[K, R, W],
) -> Result[R, KeyedStoreError] {
  guard self.entry.live && self.entry.reader is Some(reader) else {
    return Err(StaleItem)
  }
  if self.entry.liveness is Some(liveness) {
    ignore(liveness.get())
  }
  Ok(reader)
}

///|
pub fn[K, R, W] KeyedItemWrite::read(
  self : KeyedItemWrite[K, R, W],
) -> KeyedItemRead[K, R, W] {
  { entry: self.entry, }
}

///|
pub fn[K, R, W] KeyedItemWrite::fields(
  self : KeyedItemWrite[K, R, W],
) -> Result[W, KeyedStoreError] {
  guard self.entry.live && self.entry.writer is Some(writer) else {
    return Err(StaleItem)
  }
  Ok(writer)
}
