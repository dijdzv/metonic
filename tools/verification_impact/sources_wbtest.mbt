///|
fn source_fixture(
  directory : String,
  deps : Array[String],
  files : Array[String],
  tests? : Array[String] = [],
  test_deps? : Array[String] = [],
) -> Json {
  let listed : Map[String, Json] = Map([])
  let test_files : Map[String, Json] = Map([])
  for filename in tests {
    test_files[filename] = Json::object({})
  }
  for filename in files {
    listed[filename] = Json::object({})
  }
  {
    "root-path": directory,
    "is-third-party": false,
    "deps": deps.map(dep => { "fspath": dep }),
    "test-deps": test_deps.map(dep => { "fspath": dep }),
    "wbtest-deps": [],
    "files": listed,
    "test-files": test_files,
    "wbtest-files": {},
    "mbt-md-files": {},
  }
}

///|
test "only selected package tests introduce test-only dependencies" {
  let metadata : Json = {
    "packages": [
      source_fixture(
        "/app",
        ["/dep"],
        ["/app/main.mbt"],
        tests=["/app/main_test.mbt"],
        test_deps=["/helper"],
      ),
      source_fixture(
        "/dep",
        [],
        ["/dep/lib.mbt"],
        tests=["/dep/unused_test.mbt"],
        test_deps=["/absent"],
      ),
      source_fixture("/helper", [], ["/helper/lib.mbt"]),
    ],
  }
  let expected = [
    "/app/main.mbt", "/app/main_test.mbt", "/dep/lib.mbt", "/helper/lib.mbt",
  ]
  expected.sort()
  assert_eq(source_inputs([metadata], ["/app"]).files, expected)
  let rejected = try {
    ignore(source_inputs([metadata], ["/app", "/dep"]))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "source inputs traverse dependency cycles and combine target metadata" {
  let first : Json = {
    "packages": [
      source_fixture("/app", ["/dep"], ["/app/main.mbt"]),
      source_fixture("/dep", ["/app"], ["/dep/native.mbt"]),
      source_fixture("/other", [], ["/other/unused.mbt"]),
    ],
  }
  let second : Json = {
    "packages": [source_fixture("/dep", [], ["/dep/js.mbt"])],
  }
  let expected = ["/app/main.mbt", "/dep/native.mbt", "/dep/js.mbt"]
  expected.sort()
  assert_eq(source_inputs([first, second], ["/app"]).files, expected)
  let incomplete : Json = {
    "packages": [source_fixture("/app", ["/missing"], [])],
  }
  let rejected = try {
    ignore(source_inputs([incomplete], ["/app"]))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}
