///|
fn combine_dossiers(inputs : Array[Json]) -> Json raise {
  assert_false(inputs.is_empty())
  let first = obj(inputs[0]).copy()
  let tests : Array[Json] = []
  let seen : Map[String, Bool] = Map([])
  let inventories : Array[Json] = []
  let mut force_all = false
  for input in inputs {
    let d = obj(input)
    for key in ["root", "diff", "changed", "new_sources"] {
      assert_eq(
        d.get(key),
        first.get(key),
        msg="inventories must describe the same change",
      )
    }
    force_all = force_all || d.get("force_all") == Some(Json::boolean(true))
    for item in arr(d["tests"]) {
      let t = obj(item).copy()
      let id = str(t["id"])
      assert_false(
        seen.contains(id),
        msg="duplicate test identity across inventories",
      )
      seen[id] = true
      t["kind"] = t.get("kind").unwrap_or(Json::string("moon-test"))
      t["workspace"] = d.get("workspace").unwrap_or(Json::null())
      t["target"] = d.get("target").unwrap_or(Json::null())
      tests.push(Json::object(t))
    }
    inventories.push(input)
  }
  first["tests"] = Json::array(tests)
  first["kind"] = "unified"
  first["force_all"] = Json::boolean(force_all)
  first["inventories"] = Json::array(inventories)
  first["coverage"] = "Only explicitly supplied inventories; not proof of repository-wide completeness"
  Json::object(first)
}

///|
test "combined selection retains unit and integration identities" {
  let common : Map[String, Json] = {
    "root": "r",
    "diff": "d",
    "changed": [],
    "new_sources": {},
    "force_all": false,
  }
  let units = common.copy()
  units["tests"] = [{ "id": "js:p:f:0" }]
  let gates = common.copy()
  gates["tests"] = [{ "id": "gate:browser", "kind": "integration-gate" }]
  let combined = obj(
    combine_dossiers([Json::object(units), Json::object(gates)]),
  )
  assert_eq(arr(combined["tests"]).length(), 2)
  assert_eq(
    obj(arr(combined["tests"])[1])["kind"],
    Json::string("integration-gate"),
  )
}
