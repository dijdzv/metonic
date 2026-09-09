///|
async test "tree records invalidate on additions deletions and nested hidden inputs" {
  let base = ".work/verification-tree-tests-"
  let mut index = 0
  while @fs.exists(base + index.to_string()) {
    index += 1
  }
  let dir = base + index.to_string()
  let tree = dir + "/inputs"
  @fs.mkdir(tree, recursive=true)
  let config : Json = {
    "files": [],
    "trees": [tree, tree],
    "context": {
      "target": "wasm",
      "toolchain": "fixture",
      "command": "fixture",
      "policy": "fixture",
    },
  }
  let filename = dir + "/config.json"
  let record = dir + "/success.json"
  @fs.write_file(filename, config.stringify())
  record_verification(filename, record, () => ())
  assert_true(matching_record(filename, record))
  @fs.write_file(tree + "/new_test.mbt", "test {}")
  assert_false(matching_record(filename, record))
  record_verification(filename, record, () => ())
  @fs.remove(tree + "/new_test.mbt")
  assert_false(matching_record(filename, record))
  record_verification(filename, record, () => ())
  @fs.mkdir(tree + "/nested")
  assert_false(matching_record(filename, record))
  @fs.write_file(tree + "/nested/.input", "first")
  record_verification(filename, record, () => ())
  @fs.write_file(tree + "/nested/.input", "second")
  assert_false(matching_record(filename, record))
  let failed = try {
    record_verification(filename, record, () => {
      @fs.write_file(tree + "/during-test", "new dependency")
    })
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  assert_false(matching_record(filename, record))
  let context : Json = {
    "target": "wasm",
    "toolchain": "fixture",
    "command": "fixture",
    "policy": "fixture",
  }
  for invalid in [tree + "/missing", tree + "/during-test"] {
    let invalid_config : Json = {
      "files": [],
      "trees": [invalid],
      "context": context,
    }
    @fs.write_file(filename, invalid_config.stringify())
    let rejected = try {
      ignore(fingerprint(filename))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  @fs.write_file(filename, config.stringify())
  @fs.symlink(target=@fs.realpath(tree), tree + "/cycle")
  let rejected_link = try {
    ignore(fingerprint(filename))
    false
  } catch {
    _ => true
  }
  assert_true(rejected_link)
}
