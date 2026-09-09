///|
test "shared edits select both hosts through unmapped dependency nodes" {
  let graphs : Array[Array[ExportedPackage]] = [
    [
      { name: "app/shared", dependencies: [], },
      { name: "host/browser", dependencies: ["app/shared"], },
    ],
    [
      { name: "app/shared", dependencies: [], },
      { name: "external/bridge", dependencies: ["app/shared"], },
      { name: "host/native", dependencies: ["external/bridge"], },
    ],
  ]
  let owned = Map([
    ("app/shared", "C:/repo/shared"),
    ("host/browser", "C:/repo/browser"),
    ("host/native", "C:/repo/native"),
  ])
  assert_eq(select_exported(graphs, owned, ["C:/repo/shared/state.mbt"]), {
    packages: ["c:/repo/native", "c:/repo/shared", "c:/repo/browser"],
    full: false,
  })
  assert_eq(select_exported(graphs, owned, ["C:/repo/native/main.mbt"]), {
    packages: ["c:/repo/native"],
    full: false,
  })
  assert_true(select_exported(graphs, owned, ["C:/repo/moon.mod"]).full)
  assert_eq(select_exported(graphs, owned, []).packages, [])
  let rejected = try {
    ignore(select_exported([graphs[0]], owned, []))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}
