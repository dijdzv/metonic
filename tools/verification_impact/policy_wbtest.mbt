///|
test "critical and affected suites run before commit and the remainder before push" {
  let policy : Json = {
    "version": 1,
    "critical_packages": { "state": ["js", "native"], "wire": ["wasm"] },
  }
  assert_eq(
    partition_tests(policy, "js", ["state", "editor", "other"], [
      "editor", "editor",
    ]),
    (["state", "editor"], ["other"]),
  )
  assert_eq(
    partition_tests(policy, "wasm", ["state", "wire", "other"], []),
    (["wire"], ["state", "other"]),
  )
  for affected in [[], ["missing"]] {
    let rejected = try {
      ignore(partition_tests(policy, "js", ["other"], affected))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "metadata partition follows test dependencies and filters target support" {
  let policy : Json = {
    "version": 1,
    "critical_packages": { "critical": ["js"] },
  }
  let metadata : Json = {
    "source_dir": "C:/repo",
    "packages": [
      fixture_package("C:/repo/core", []),
      fixture_package("C:/repo/consumer", [], test_deps=["C:/repo/core"]),
      fixture_package("C:/repo/critical", []),
      fixture_package("C:/repo/wasm_only", ["C:/repo/core"], targets=["Wasm"]),
      fixture_package("C:/repo/unrelated", []),
    ],
  }
  assert_eq(
    partition_metadata(policy, "js", metadata, ["C:/repo/core/changed.mbt"]),
    (["core", "consumer", "critical"], ["unrelated"]),
  )
  assert_eq(
    partition_metadata(policy, "js", metadata, ["C:/repo/moon.mod"]),
    (["core", "consumer", "critical", "unrelated"], []),
  )
  assert_eq(
    partition_metadata(policy, "wasm", metadata, ["C:/repo/core/changed.mbt"]),
    (["core", "consumer", "wasm_only"], ["critical", "unrelated"]),
  )
}
