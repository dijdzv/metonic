///|
async test "fingerprints distinguish contents and execution context but not input order" {
  let base = ".work/fingerprint-tests-"
  let mut index = 0
  while @fs.exists(base + index.to_string()) {
    index = index + 1
  }
  let dir = base + index.to_string()
  @fs.mkdir(dir, recursive=true)
  @fs.write_file(dir + "/a", "first")
  @fs.write_file(dir + "/b", "second")
  let context : Json = {
    "target": "wasm",
    "toolchain": "fixture",
    "command": "fixture",
    "policy": "fixture",
  }
  let config : Json = { "files": [dir + "/a", dir + "/b"], "context": context }
  let reordered : Json = {
    "files": [dir + "/b", dir + "/a", dir + "/a"],
    "context": context,
  }
  @fs.write_file(dir + "/config.json", config.stringify())
  @fs.write_file(dir + "/reordered.json", reordered.stringify())
  let initial = fingerprint(dir + "/config.json").stringify()
  assert_eq(initial, fingerprint(dir + "/reordered.json").stringify())
  @fs.write_file(dir + "/a", "changed")
  assert_false(initial == fingerprint(dir + "/config.json").stringify())
  @fs.write_file(dir + "/a", "first")
  assert_eq(initial, fingerprint(dir + "/config.json").stringify())
  let changed : Json = {
    "files": [dir + "/a", dir + "/b"],
    "context": {
      "target": "native",
      "toolchain": "fixture",
      "command": "fixture",
      "policy": "fixture",
    },
  }
  @fs.write_file(dir + "/changed.json", changed.stringify())
  assert_false(initial == fingerprint(dir + "/changed.json").stringify())
  let invalid_configs : Array[Json] = [
    { "files": [], "context": context },
    { "files": [dir + "/missing"], "context": context },
    { "files": [dir + "/a"], "context": { "target": "wasm" } },
  ]
  for invalid in invalid_configs {
    @fs.write_file(dir + "/invalid.json", invalid.stringify())
    let rejected = try {
      ignore(fingerprint(dir + "/invalid.json"))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}
