///|
async test "success records require successful execution and unchanged inputs" {
  let base = ".work/verification-record-tests-"
  let mut index = 0
  while @fs.exists(base + index.to_string()) {
    index = index + 1
  }
  let dir = base + index.to_string()
  @fs.mkdir(dir, recursive=true)
  @fs.write_file(dir + "/input", "original")
  let config : Json = {
    "files": [dir + "/input"],
    "context": {
      "target": "wasm",
      "toolchain": "fixture",
      "command": "fixture",
      "policy": "fixture",
    },
  }
  @fs.write_file(dir + "/config.json", config.stringify())
  let record = dir + "/result.json"
  assert_false(matching_record(dir + "/config.json", record))
  record_verification(dir + "/config.json", record, () => ())
  assert_true(matching_record(dir + "/config.json", record))
  let saved : Map[String, Json] = @json.from_json(
    @json.parse(@fs.read_file(record).text()),
  )
  assert_eq(saved.get("success"), Some(Json::boolean(true)))
  let failed = try {
    record_verification(dir + "/config.json", record, () => {
      fail("verification failed")
    })
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  assert_false(matching_record(dir + "/config.json", record))
  assert_eq(@fs.read_file(record).text(), "{\"success\":false}")
  let changed = try {
    record_verification(dir + "/config.json", record, () => {
      @fs.write_file(dir + "/input", "changed")
    })
    false
  } catch {
    _ => true
  }
  assert_true(changed)
  assert_eq(@fs.read_file(record).text(), "{\"success\":false}")
  assert_false(@fs.exists(record + ".lock"))
  let mut entered = false
  let cancelled = try {
    @async.with_timeout(1000, () => {
      record_verification(dir + "/config.json", record, () => {
        entered = true
        @async.sleep(5000)
      })
    })
    false
  } catch {
    _ => true
  }
  assert_true(entered && cancelled)
  assert_eq(@fs.read_file(record).text(), "{\"success\":false}")
  assert_false(@fs.exists(record + ".lock"))
  record_verification(dir + "/config.json", record, () => ())
  let completed = @fs.read_file(record).text()
  @fs.mkdir(record + ".lock")
  let collision = try {
    record_verification(dir + "/config.json", record, () => fail("must not run"))
    false
  } catch {
    _ => true
  }
  assert_true(collision)
  assert_eq(@fs.read_file(record).text(), completed)
  assert_true(@fs.exists(record + ".lock"))
  @fs.rmdir(record + ".lock")
  @fs.write_file(dir + "/input", "another change")
  assert_false(matching_record(dir + "/config.json", record))
  for
    contents in ["not json", "[]", "{\"success\":true}", "{\"success\":false}"] {
    @fs.write_file(record, contents)
    assert_false(matching_record(dir + "/config.json", record))
  }
}
