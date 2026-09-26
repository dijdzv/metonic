///|
async fn evaluation_report(manifest : Json, directory : String) -> Json {
  let rows : Array[Json] = []
  let pending : Array[Json] = []
  for entry in arr(obj(manifest)["cases"]) {
    let case = obj(entry)
    let name = str(case["name"])
    for repetition in 1..<4 {
      let stem = directory +
        "/frozen-" +
        name +
        "-compact-" +
        repetition.to_string()
      let mut response_path = stem + "-response.json"
      if repetition == 1 && (name == "label" || name == "navigation") {
        response_path = directory + "/compact-" + name + "-response.json"
      }
      if !@fs.exists(response_path) {
        pending.push({ "case": case["name"], "repeat": repetition })
        continue
      }
      let response = obj(read_json(response_path))
      let dossier = read_json(directory + "/frozen-" + name + "-dossier.json")
      let d = obj(dossier)
      assert_eq(response["binding"], dossier, msg="stale evaluation binding")
      assert_eq(d["diff"], case["diff"], msg="case diff changed")
      let records = obj(response["records"])
      let omitted : Array[Json] = []
      let model_missed : Array[Json] = []
      let final_missed : Array[Json] = []
      let missing : Array[Json] = []
      let expected = arr(case["expected_ids"])
      let mut expected_found = 0
      for item in arr(d["tests"]) {
        let item_fields = obj(item)
        let id = str(item_fields["id"])
        let answer = match records.get(id) {
          Some(Object(record)) => record.get("answer")
          _ => None
        }
        if answer == None || answer == Some(Json::null()) {
          missing.push(item_fields["id"])
        }
        let model_run = @policy.select(answer, 0.5, 0.6)
        let required = item_fields.get("required") == Some(Json::boolean(true)) ||
          d["force_all"] == Json::boolean(true) ||
          arr(d["changed"]).contains(item_fields["file"])
        if !model_run && !required {
          omitted.push(item_fields["id"])
        }
        if expected.contains(item_fields["id"]) {
          expected_found += 1
          if !model_run {
            model_missed.push(item_fields["id"])
            if !required {
              final_missed.push(item_fields["id"])
            }
          }
        }
      }
      assert_eq(expected_found, expected.length(), msg="expected ID missing")
      let mut input_tokens = 0.0
      for batch in arr(response["batches"]) {
        if obj(batch).get("usage") is Some(Object(usage)) {
          if usage.get("input_tokens") is Some(Number(n, ..)) {
            input_tokens += n
          }
        }
      }
      rows.push({
        "case": case["name"],
        "split": case["split"],
        "evidence": case["evidence"],
        "repeat": repetition,
        "items": arr(d["tests"]).length(),
        "records": records.length(),
        "missing_answers": missing,
        "expected_count": expected_found,
        "model_missed": model_missed,
        "final_missed": final_missed,
        "omitted_count": omitted.length(),
        "omitted_ids": omitted,
        "input_tokens": Json::number(input_tokens),
        "elapsed_ms": response["elapsed_ms"],
      })
    }
  }
  { "runs": rows, "pending": pending }
}
