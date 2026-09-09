///|
fn fixture_package(
  path : String,
  deps : Array[String],
  test_deps? : Array[String] = [],
  wb_deps? : Array[String] = [],
  third_party? : Bool = false,
) -> Json {
  fn edges(paths : Array[String]) -> Json {
    Json::array(paths.map(path => { "fspath": path }))
  }
  {
    "root-path": path,
    "is-third-party": third_party,
    "deps": edges(deps),
    "test-deps": edges(test_deps),
    "wbtest-deps": edges(wb_deps),
  }
}

///|
test "changes reach transitive consumers and test-only imports" {
  let metadata : Json = {
    "packages": [
      fixture_package("C:/repo/a", []),
      fixture_package("C:/repo/b", ["C:/repo/a"]),
      fixture_package("C:/repo/c", [], test_deps=["C:/repo/b"]),
      fixture_package("C:/repo/d", [], wb_deps=["C:/repo/c"]),
      fixture_package("C:/repo/independent", []),
    ],
  }
  assert_eq(select(metadata, ["C:\\REPO\\a\\changed.mbt"]).packages, [
    "c:/repo/a", "c:/repo/b", "c:/repo/c", "c:/repo/d",
  ])
  assert_eq(select(metadata, []), { packages: [], full: false, })
  assert_true(select(metadata, ["C:/repo/moon.mod"]).full)
  assert_true(select(metadata, ["C:/repo/new/file.mbt"]).full)
}

///|
test "nested package ownership and dependency cycles terminate" {
  let metadata : Json = {
    "packages": [
      fixture_package("C:/repo/a", ["C:/repo/a/nested"]),
      fixture_package("C:/repo/a/nested", ["C:/repo/a"]),
      fixture_package("C:/repo/ab", []),
    ],
  }
  assert_eq(select(metadata, ["C:/repo/a/nested/test.mbt"]).packages, [
    "c:/repo/a", "c:/repo/a/nested",
  ])
}

///|
test "third party changes invalidate consumers but are not test destinations" {
  let metadata : Json = {
    "packages": [
      fixture_package("C:/deps/lib", [], third_party=true),
      fixture_package("C:/repo/app", ["C:/deps/lib"]),
    ],
  }
  assert_eq(select(metadata, ["C:/deps/lib/bridge.c"]).packages, ["c:/repo/app"])
}

///|
test "incomplete metadata cannot produce a successful empty selection" {
  let malformed : Json = {
    "packages": [
      { "root-path": "C:/repo/a", "is-third-party": false, "deps": [] },
    ],
  }
  let rejected = try {
    ignore(select(malformed, ["C:/repo/a/file.mbt"]))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "workspace and target graphs retain every dependency edge" {
  let root : Json = {
    "packages": [
      fixture_package("C:/repo/shared", []),
      fixture_package("C:/repo/codec", []),
    ],
  }
  let native : Json = {
    "packages": [
      fixture_package("C:/repo/shared", ["C:/repo/codec"], third_party=true),
      fixture_package("C:/repo/native", ["C:/repo/shared"]),
    ],
  }
  let browser : Json = {
    "packages": [
      fixture_package("C:/repo/shared", [], third_party=true),
      fixture_package("C:/repo/browser", [], test_deps=["C:/repo/shared"]),
    ],
  }
  assert_eq(
    select_many([root, native, browser], ["C:/repo/codec/changed.mbt"]).packages,
    ["c:/repo/shared", "c:/repo/codec", "c:/repo/native", "c:/repo/browser"],
  )
  assert_eq(select_many([native, root], ["C:/repo/shared/test.mbt"]).packages, [
    "c:/repo/shared", "c:/repo/native",
  ])
}
