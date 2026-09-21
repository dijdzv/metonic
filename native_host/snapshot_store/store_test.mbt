///|
async test "snapshot survives reopening and replacement" {
  let directory = @fs.tmpdir(prefix="metonic-snapshot-")
  defer @fs.rmdir(directory, recursive=true)
  let store = open(directory)
  assert_eq(store.load(), None)
  store.save(b"first")
  store.save(b"second")
  store.close()
  let restored = open(directory)
  defer restored.close()
  assert_eq(restored.load(), Some(b"second"))
}

///|
async test "another owner cannot overwrite a live store" {
  let directory = @fs.tmpdir(prefix="metonic-snapshot-lock-")
  defer @fs.rmdir(directory, recursive=true)
  let store = open(directory)
  defer store.close()
  let refused = try {
    let second = open(directory)
    second.close()
    false
  } catch {
    Failure::InUse => true
    error => raise error
  }
  assert_true(refused)
}

///|
async test "failed staging preserves the previous snapshot and retry succeeds" {
  let directory = @fs.tmpdir(prefix="metonic-snapshot-failure-")
  defer @fs.rmdir(directory, recursive=true)
  let store = open(directory)
  defer store.close()
  store.save(b"original")
  @fs.mkdir(directory + "/snapshot.pending")
  let failed = try {
    store.save(b"replacement")
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  assert_eq(store.load(), Some(b"original"))
  @fs.rmdir(directory + "/snapshot.pending")
  store.save(b"replacement")
  assert_eq(store.load(), Some(b"replacement"))
}

///|
async test "closed stores reject later IO" {
  let directory = @fs.tmpdir(prefix="metonic-snapshot-closed-")
  defer @fs.rmdir(directory, recursive=true)
  let store = open(directory)
  store.close()
  let rejected = try {
    ignore(store.load())
    false
  } catch {
    Failure::Closed => true
    error => raise error
  }
  assert_true(rejected)
}
