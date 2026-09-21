///|
pub suberror Failure {
  InUse
  Closed
  TooLarge
  Busy
} derive(Debug)

///|
pub struct Store {
  priv directory : String
  priv lock : @fs.File
  priv mut closed : Bool
  priv mut busy : Bool
}

///|
pub async fn open(directory : String) -> Store {
  if !@fs.exists(directory) {
    @fs.mkdir(directory, recursive=true)
  }
  let lock = @fs.open(
    directory + "/writer.lock",
    mode=ReadWrite,
    create_mode=OpenOrCreate,
  )
  errdefer lock.close()
  guard lock.try_lock(Exclusive) else { raise InUse }
  { directory, lock, closed: false, busy: false, }
}

///|
fn Store::begin(self : Store) -> Unit raise {
  guard !self.closed else { raise Closed }
  guard !self.busy else { raise Busy }
  self.busy = true
}

///|
pub async fn Store::load(self : Store) -> Bytes? {
  self.begin()
  defer {
    self.busy = false
  }
  let path = self.directory + "/snapshot"
  if !@fs.exists(path) {
    return None
  }
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let size = file.size()
  guard size <= 1048576L else { raise TooLarge }
  Some(file.read_exactly_at(size.to_int(), position=0L))
}

///|
pub async fn Store::save(self : Store, bytes : Bytes) -> Unit {
  guard bytes.length() <= 1048576 else { raise TooLarge }
  self.begin()
  defer {
    self.busy = false
  }
  let temporary = self.directory + "/snapshot.pending"
  // The live snapshot is never truncated. A failed or canceled staging write
  // may leave this private file; the next save replaces it under the same lock.
  @fs.write_file(temporary, bytes, sync=Full)
  @fs.rename(temporary, self.directory + "/snapshot", replace=true)
}

///|
pub fn Store::close(self : Store) -> Unit raise {
  guard !self.closed else { return }
  // Releasing the lock while a write runs would permit another owner to reuse
  // the staging path. The host must await task cleanup before closing storage.
  guard !self.busy else { raise Busy }
  self.closed = true
  self.lock.close()
}
