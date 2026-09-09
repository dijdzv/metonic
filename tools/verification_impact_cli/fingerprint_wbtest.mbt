///|
async test "batched hashes preserve every path across Windows command length boundaries" {
  let dir = @fs.tmpdir(prefix="metonic-fingerprint-batch")
  defer @async.protect_from_cancel(() => @fs.rmdir(dir, recursive=true))
  let files : Array[String] = []
  for index = 0; index < 160; index = index + 1 {
    let filename = dir +
      "/日本語 space long-file-name-for-command-boundary-" +
      index.to_string() +
      ".txt"
    @fs.write_file(filename, "same raw content\r\n")
    files.push(filename)
  }
  let config : Json = {
    "files": files,
    "context": {
      "target": "wasm",
      "toolchain": "fixture",
      "command": "fixture",
      "policy": "fixture",
    },
  }
  @fs.write_file(dir + "/config.json", config.stringify())
  let result : Map[String, Json] = @json.from_json(
    fingerprint(dir + "/config.json"),
  )
  let inputs : Array[Map[String, Json]] = @json.from_json(
    result.get("inputs").unwrap(),
  )
  assert_eq(inputs.length(), files.length())
  let (code, output, _) = @process.collect_output(
    "git",
    ["hash-object", "--no-filters", "--", files[0]],
    no_console_window=true,
  )
  assert_eq(code, 0)
  let expected = Json::string(output.text().trim().to_owned())
  let paths : Array[String] = []
  for input in inputs {
    assert_eq(input.get("blob"), Some(expected))
    let path : String = @json.from_json(input.get("path").unwrap())
    assert_false(paths.contains(path))
    paths.push(path)
  }
  for filename in files {
    assert_true(
      paths.contains(@fs.realpath(filename).replace_all(old="\\", new="/")),
    )
  }
}

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
