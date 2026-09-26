///|
pub(all) enum Failure {
  TooLarge
  AccessDenied
  CapacityExceeded
  Busy
  Closed
  InvalidData
  Failed
} derive(Eq, Debug)

///|
pub fn max_utf8_bytes() -> Int {
  1_048_576
}

///|
pub struct Snapshot {
  priv load_impl : async () -> Result[String?, Failure]
  priv save_impl : async (String) -> Result[Unit, Failure]
  priv mut busy : Bool
}

///|
pub fn Snapshot::new(
  load : async () -> Result[String?, Failure],
  save : async (String) -> Result[Unit, Failure],
) -> Snapshot {
  { load_impl: load, save_impl: save, busy: false, }
}

///|
pub async fn Snapshot::load(self : Snapshot) -> Result[String?, Failure] {
  guard !self.busy else { return Err(Busy) }
  self.busy = true
  defer {
    self.busy = false
  }
  match (self.load_impl)() {
    Ok(Some(value)) if @utf8.encode(value).length() > max_utf8_bytes() =>
      Err(TooLarge)
    result => result
  }
}

///|
pub async fn Snapshot::save(
  self : Snapshot,
  value : String,
) -> Result[Unit, Failure] {
  guard @utf8.encode(value).length() <= max_utf8_bytes() else {
    return Err(TooLarge)
  }
  guard !self.busy else { return Err(Busy) }
  self.busy = true
  defer {
    self.busy = false
  }
  (self.save_impl)(value)
}
