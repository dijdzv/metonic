///|
test "export preserves test-only imports and normalizes package labels" {
  let graph =
    #|digraph DepRelationship {
    #|    rankdir=TB;
    #|    node [shape=box style="filled,rounded"];
    #|    "PackageId(1v1)@Source" [label="local/app\nSource" fillcolor="lightblue"];
    #|    "PackageId(1v1)@BlackboxTest" [label="local\napp\nBlackboxTest" fillcolor="lightcoral"];
    #|    "PackageId(2v1)@Source" [label="local\nhelper\nSource" fillcolor="lightblue"];
    #|    "PackageId(1v1)@BlackboxTest" -> "PackageId(2v1)@Source" [label="helper"];
    #|    "PackageId(1v1)@BlackboxTest" -> "PackageId(1v1)@Source" [label="app"];
    #|}
  assert_eq(read_package_graph(graph), [
    { name: "local/app", dependencies: ["local/helper"], },
    { name: "local/helper", dependencies: [], },
  ])
  for
    invalid in [
      graph.replace_all(
        old="    \"PackageId(2v1)@Source\" [label",
        new="    \"PackageId(3v1)@Source\" [label",
      ),
      graph.replace_all(old="BlackboxTest", new="UnknownTest"),
      graph + "\nunexpected",
      "digraph DepRelationship {\n}",
    ] {
    let rejected = try {
      ignore(read_package_graph(invalid))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}
