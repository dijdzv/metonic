///|
fn chunk_gates(input : Json) -> Json raise {
  let d = obj(input).copy()
  assert_eq(d["kind"], Json::string("integration-gates"))
  let chunks : Array[Json] = []
  let parents = arr(d["tests"])
  for item in parents {
    let t = obj(item)
    let contract = obj(@json.parse(str(t["test_body"])))
    let groups : Array[Array[Json]] = [[]]
    let mut size = 0
    for observation in arr(contract["observations"]) {
      let length = observation.stringify().length()
      if size + length > 12000 && !groups[groups.length() - 1].is_empty() {
        groups.push([])
        size = 0
      }
      groups[groups.length() - 1].push(observation)
      size += length
    }
    for i, group in groups {
      let chunk = t.copy()
      let evidence = contract.copy()
      evidence["observations"] = Json::array(group)
      evidence["selection_scope"] = "One observation chunk of a larger gate; consider shared setup and indirect effects. The gate may be skipped only if every chunk is unrelated."
      chunk["id"] = Json::string(str(t["id"]) + ":chunk:" + i.to_string())
      chunk["parent_id"] = t["id"]
      chunk["test_body"] = Json::string(Json::object(evidence).stringify())
      chunks.push(Json::object(chunk))
    }
  }
  d["gate_parents"] = Json::array(parents)
  d["tests"] = Json::array(chunks)
  Json::object(d)
}

///|
fn fold_gate_chunks(plan : Json) -> Json {
  let d = obj(plan).copy()
  let expected = arr(d["tests"])
  let selections = arr(d["selections"])
  let folded : Array[Json] = []
  for parent in arr(d["gate_parents"]) {
    let id = obj(parent)["id"]
    let children = expected.filter(t => obj(t)["parent_id"] == id)
    let run = children.is_empty() ||
      children.any(child => {
        let matches = selections.filter(s => {
          obj(obj(s)["test"])["id"] == obj(child)["id"]
        })
        matches.length() != 1 ||
        obj(matches[0]).get("run") != Some(Json::boolean(false))
      })
    folded.push({ "test": parent, "run": Json::boolean(run) })
  }
  d["chunk_selections"] = d["selections"]
  d["selections"] = Json::array(folded)
  d["tests"] = d["gate_parents"]
  Json::object(d)
}

///|
test "a missing or needed evidence chunk keeps the whole gate" {
  let parent : Json = { "id": "gate:x" }
  let a : Json = { "id": "a", "parent_id": "gate:x" }
  let b : Json = { "id": "b", "parent_id": "gate:x" }
  let cases : Array[Array[Json]] = [
    [{ "test": a, "run": false }],
    [{ "test": a, "run": false }, { "test": b, "run": true }],
    [{ "test": a, "run": false }, { "test": b, "run": false }],
  ]
  for selections in cases {
    let result = obj(
      fold_gate_chunks({
        "tests": [a, b],
        "gate_parents": [parent],
        "selections": Json::array(selections),
      }),
    )
    assert_eq(
      obj(arr(result["selections"])[0])["run"],
      Json::boolean(
        selections.length() == 1 ||
        obj(selections[1])["run"] == Json::boolean(true),
      ),
    )
  }
}

///|
test "chunking preserves every observation and incomplete evidence stays required" {
  let observations : Array[Json] = Array::make(
    300,
    Json::string(
      "an observation containing enough text to require multiple chunks",
    ),
  )
  let contract : Json = { "observations": Json::array(observations) }
  let result = obj(
    chunk_gates({
      "kind": "integration-gates",
      "tests": [
        {
          "id": "gate:x",
          "required": true,
          "test_body": Json::string(contract.stringify()),
        },
      ],
    }),
  )
  let chunks = arr(result["tests"])
  assert_true(chunks.length() > 1)
  let recovered : Array[Json] = []
  for chunk in chunks {
    let t = obj(chunk)
    assert_eq(t["required"], Json::boolean(true))
    for
      observation in arr(obj(@json.parse(str(t["test_body"])))["observations"]) {
      recovered.push(observation)
    }
  }
  assert_eq(recovered, observations)
}
