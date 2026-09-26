///|
fn load_typed(key : String) -> Result[String?, @snapshot.Failure] {
  match storage_access() {
    Ok(storage) => Ok(storage.get_item(key))
    Err(error) => Err(error)
  }
}

///|
fn save_typed(key : String, value : String) -> Result[Unit, @snapshot.Failure] {
  match storage_access() {
    Err(error) => Err(error)
    Ok(storage) =>
      match storage.set_item(key, value) {
        Ok(_) => Ok(())
        Err(@dom.StorageSetItemError::QuotaExceededError(_)) =>
          Err(@snapshot.CapacityExceeded)
        Err(_) => Err(@snapshot.Failed)
      }
  }
}
