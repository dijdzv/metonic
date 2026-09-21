///|
fn storage_window() -> @dom.Window = "websys" "input_window"

///|
pub fn load(key : String) -> Result[String?, String] {
  match storage_window().local_storage() {
    Ok(storage) => Ok(storage.get_item(key))
    Err(error) => Err("Storage access failed: " + @debug.to_string(error))
  }
}

///|
pub fn save(key : String, value : String) -> Result[Unit, String] {
  match storage_window().local_storage() {
    Err(error) => Err("Storage access failed: " + @debug.to_string(error))
    Ok(storage) =>
      match storage.set_item(key, value) {
        Ok(_) => Ok(())
        Err(error) => Err("Storage write failed: " + @debug.to_string(error))
      }
  }
}
