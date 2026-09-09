///|
test "workspace scope retains dependencies outside its execution directory" {
  let policy : Json = { "version": 1, "critical_packages": {} }
  let metadata : Json = {
    "source_dir": "C:/repo/browser_host",
    "packages": [
      fixture_package("C:/repo/shared", []),
      fixture_package("C:/repo/browser_host/app", ["C:/repo/shared"]),
      fixture_package("C:/repo/browser_host/app/probe", [
        "C:/repo/browser_host/app",
      ]),
      fixture_package("C:/repo/browser_host/app/independent", []),
      fixture_package("C:/repo/browser_host/application", []),
    ],
  }
  assert_eq(
    partition_metadata(
      policy,
      "js",
      metadata,
      ["C:/repo/shared/value.mbt"],
      scope="C:/repo/browser_host/app",
    ),
    ([".", "probe"], ["independent"]),
  )
  assert_eq(
    partition_metadata(
      policy,
      "js",
      metadata,
      ["C:/repo/moon.mod"],
      scope="C:/repo/browser_host/app",
    ),
    ([".", "probe", "independent"], []),
  )
  let rejected = try {
    ignore(partition_metadata(policy, "js", metadata, []))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  let empty_scope = try {
    ignore(
      partition_metadata(policy, "js", metadata, [], scope="C:/repo/missing"),
    )
    false
  } catch {
    _ => true
  }
  assert_true(empty_scope)
}

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
