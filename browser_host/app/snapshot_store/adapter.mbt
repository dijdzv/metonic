///|
pub fn text_snapshot(key : String) -> @snapshot.Snapshot {
  @snapshot.Snapshot::new(() => load_typed(key), value => save_typed(key, value))
}
