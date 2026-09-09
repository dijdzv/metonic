///|
test "verification inputs include transitive test and external dependencies" {
  let graphs : Array[Array[ExportedPackage]] = [
    [
      { name: "app", dependencies: ["shared"], },
      { name: "shared", dependencies: ["external"], },
      { name: "external", dependencies: [], },
      { name: "unrelated", dependencies: [], },
    ],
    [
      { name: "app", dependencies: ["test_helper"], },
      { name: "test_helper", dependencies: ["app"], },
    ],
  ]
  let expected = ["app", "shared", "external", "test_helper"]
  expected.sort()
  assert_eq(dependency_inputs(graphs, ["app"]), expected)
  assert_eq(dependency_inputs(graphs, []), [])
  let unknown_rejected = try {
    ignore(dependency_inputs(graphs, ["missing"]))
    false
  } catch {
    _ => true
  }
  assert_true(unknown_rejected)
  let incomplete : Array[Array[ExportedPackage]] = [
    [{ name: "app", dependencies: ["missing"], }],
  ]
  let rejected = try {
    ignore(dependency_inputs(incomplete, ["app"]))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}
