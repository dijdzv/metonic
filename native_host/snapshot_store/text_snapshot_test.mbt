///|
async test "text snapshot adapter restores unicode and distinguishes absence" {
  let directory = @fs.tmpdir(prefix="metonic-text-snapshot-")
  defer @fs.rmdir(directory, recursive=true)
  let store = open(directory)
  let snapshot = store.text_snapshot()
  assert_eq(snapshot.load(), Ok(None))
  assert_eq(snapshot.save("日本語😀"), Ok(()))
  store.close()
  let restored = open(directory)
  defer restored.close()
  assert_eq(restored.text_snapshot().load(), Ok(Some("日本語😀")))
  assert_eq(snapshot.load(), Err(@snapshot.Closed))
}

///|
async test "text snapshot adapter reports invalid UTF-8 without replacing data" {
  let directory = @fs.tmpdir(prefix="metonic-text-invalid-")
  defer @fs.rmdir(directory, recursive=true)
  let store = open(directory)
  defer store.close()
  store.save(b"\xff")
  let snapshot = store.text_snapshot()
  assert_eq(snapshot.load(), Err(@snapshot.InvalidData))
  assert_eq(snapshot.save("recovered"), Ok(()))
  assert_eq(snapshot.load(), Ok(Some("recovered")))
}

///|
async test "text snapshot adapter maps failed staging and retains the old value" {
  let directory = @fs.tmpdir(prefix="metonic-text-failure-")
  defer @fs.rmdir(directory, recursive=true)
  let store = open(directory)
  defer store.close()
  let snapshot = store.text_snapshot()
  assert_eq(snapshot.save("previous"), Ok(()))
  @fs.mkdir(directory + "/snapshot.pending")
  assert_eq(snapshot.save("next"), Err(@snapshot.Failed))
  assert_eq(snapshot.load(), Ok(Some("previous")))
  @fs.rmdir(directory + "/snapshot.pending")
}
