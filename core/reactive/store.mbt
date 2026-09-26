///|
pub struct Store {
  priv owner : Scope
}

///|
pub fn Store::new(owner : Scope) -> Store {
  owner.assert_alive()
  { owner, }
}

///|
pub fn[T : Eq] Store::field(self : Store, initial : T) -> StoreField[T] {
  StoreField::new(self.owner, initial)
}

///|
pub fn[T] Store::field_by(
  self : Store,
  initial : T,
  equal : (T, T) -> Bool,
) -> StoreField[T] {
  StoreField::new_by(self.owner, initial, equal)
}

///|
pub fn[T] Store::batch(self : Store, f : () -> T) -> T {
  self.owner.assert_alive()
  self.owner.graph().batch(f)
}

///|
pub struct StoreField[T] {
  priv value : Signal[T]
}

///|
fn[T : Eq] StoreField::new(owner : Scope, initial : T) -> StoreField[T] {
  { value: Signal::new(owner, initial), }
}

///|
fn[T] StoreField::new_by(
  owner : Scope,
  initial : T,
  equal : (T, T) -> Bool,
) -> StoreField[T] {
  { value: Signal::new_by(owner, initial, equal), }
}

///|
pub fn[T] StoreField::read(self : StoreField[T]) -> StoreRead[T] {
  { value: self.value, }
}

///|
pub fn[T] StoreField::set(self : StoreField[T], next : T) -> Unit {
  self.value.set(next)
}

///|
pub fn[T] StoreField::update(self : StoreField[T], change : (T) -> T) -> Unit {
  self.value.update(change)
}

///|
pub struct StoreRead[T] {
  priv value : Signal[T]
}

///|
pub fn[T] StoreRead::get(self : StoreRead[T]) -> T {
  self.value.get()
}

///|
pub fn[T] StoreRead::peek(self : StoreRead[T]) -> T {
  self.value.peek()
}
