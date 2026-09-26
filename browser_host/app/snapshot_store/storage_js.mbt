///|
extern "js" fn storage_window() -> @dom.Window =
  #| () => window

///|
pub fn load(key : String) -> Result[String?, String] {
  match storage_window().get_local_storage() {
    Ok(storage) => Ok(storage.get_item(key))
    Err(error) => Err("Storage access failed: " + @debug.to_string(error))
  }
}

///|
pub fn save(key : String, value : String) -> Result[Unit, String] {
  match storage_window().get_local_storage() {
    Err(error) => Err("Storage access failed: " + @debug.to_string(error))
    Ok(storage) =>
      match storage.set_item(key, value) {
        Ok(_) => Ok(())
        Err(error) => Err("Storage write failed: " + @debug.to_string(error))
      }
  }
}

///|
fn storage_access() -> Result[@dom.Storage, @snapshot.Failure] {
  match storage_window().get_local_storage() {
    Ok(storage) => Ok(storage)
    Err(@dom.WindowGetLocalStorageError::SecurityError(_)) =>
      Err(@snapshot.AccessDenied)
    Err(_) => Err(@snapshot.Failed)
  }
}
