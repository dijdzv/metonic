///|
async test "environment records distinguish absent empty and changed values without plaintext" {
  let dir = @fs.tmpdir(prefix="metonic-environment-input")
  let name = "METONIC_FINGERPRINT_ENVIRONMENT_TEST"
  let original = @env.get_env_var(name)
  defer (match original {
    Some(value) => @env.set_env_var(name, value)
    None => @env.unset_env_var(name)
  })
  @fs.write_file(dir + "/input", "stable")
  let config : Json = {
    "files": [dir + "/input"],
    "environment": [name, name],
    "context": {
      "target": "fixture",
      "toolchain": "fixture",
      "command": "fixture",
      "policy": "fixture",
    },
  }
  let path = dir + "/config.json"
  @fs.write_file(path, config.stringify())
  @env.unset_env_var(name)
  let absent = fingerprint(path)
  @env.set_env_var(name, "")
  let empty = fingerprint(path)
  assert_false(absent == empty)
  @env.set_env_var(name, "private-test-value-not-for-record")
  let changed = fingerprint(path)
  assert_false(changed == empty)
  assert_false(
    changed.stringify().contains("private-test-value-not-for-record"),
  )
  assert_eq(changed, fingerprint(path))
  let fields : Map[String, Json] = @json.from_json(changed)
  let values : Array[Json] = @json.from_json(fields["environment"])
  assert_eq(values.length(), 1)
}
