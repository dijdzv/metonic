///|
pub struct Storage {
  directory : String
  mut opened : @store.Store?
  mut closed : Bool
}

///|
pub fn create(directory : String) -> Storage {
  { directory, opened: None, closed: false, }
}

///|
async fn Storage::ensure_open(
  self : Storage,
) -> Result[@store.Store, @snapshot.Failure] {
  guard !self.closed else { return Err(@snapshot.Closed) }
  if self.opened is Some(store) {
    return Ok(store)
  }
  try {
    let store = @store.open(self.directory)
    self.opened = Some(store)
    Ok(store)
  } catch {
    error if @async.is_cancellation_error(error) => raise error
    @store.InUse => Err(@snapshot.Busy)
    _ => Err(@snapshot.Failed)
  }
}

///|
pub fn Storage::snapshot(self : Storage) -> @snapshot.Snapshot {
  @snapshot.Snapshot::new(
    () => {
      match self.ensure_open() {
        Ok(store) => store.text_snapshot().load()
        Err(error) => Err(error)
      }
    },
    text => {
      match self.ensure_open() {
        Ok(store) => store.text_snapshot().save(text)
        Err(error) => Err(error)
      }
    },
  )
}

///|
pub fn Storage::close(self : Storage) -> Unit raise {
  guard !self.closed else { return }
  if self.opened is Some(store) {
    store.close()
    self.opened = None
  }
  self.closed = true
}
