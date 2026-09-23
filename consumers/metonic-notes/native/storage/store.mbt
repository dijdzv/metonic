///|
pub struct Storage {
  priv directory : String
  priv mut opened : @snapshot_store.Store?
}

///|
pub fn create(directory : String) -> Storage {
  { directory, opened: None }
}

///|
pub fn Storage::adapter(self : Storage) -> @persistence.Store {
  {
    load: () => {
      try {
        let store = match self.opened {
          Some(store) => store
          None => {
            let store = @snapshot_store.open(self.directory)
            self.opened = Some(store)
            store
          }
        }
        match store.load() {
          None => Ok(None)
          Some(bytes) => Ok(Some(@utf8.decode(bytes)))
        }
      } catch {
        error if @async.is_cancellation_error(error) => raise error
        error => Err(error.to_string())
      }
    },
    save: text => {
      try {
        guard self.opened is Some(store) else { return Err("Load storage before saving") }
        store.save(@utf8.encode(text))
        Ok(())
      } catch {
        error if @async.is_cancellation_error(error) => raise error
        error => Err(error.to_string())
      }
    },
  }
}

///|
pub fn Storage::dispose(self : Storage) -> Unit raise {
  if self.opened is Some(store) {
    store.close()
    self.opened = None
  }
}
