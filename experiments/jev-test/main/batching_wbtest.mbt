///|
test "questions are not split by an arbitrary count limit" {
  let tests : Array[Json] = []
  for i = 0; i < 257; i = i + 1 {
    tests.push({
      "id": Json::string(i.to_string()),
      "name": "sample",
      "package": "fixture",
      "file": "test.mbt",
      "index": Json::string(i.to_string()),
      "source_file_text": "test { assert_eq(1, 1) }",
      "symbols": Json::null(),
    })
  }
  let dossier : Json = {
    "tests": Json::array(tests),
    "diff": "small change",
    "changed": [],
    "new_sources": {},
    "force_all": false,
  }
  let batches = requests(dossier, "source")
  assert_eq(batches.length(), 1)
  let seen : Map[String, Bool] = Map([])
  for batch in batches {
    let questions = obj(obj(batch)["questions"])

    for id, _ in questions {
      assert_false(seen.contains(id))
      seen[id] = true
    }
  }
  assert_eq(seen.length(), 257)
}
