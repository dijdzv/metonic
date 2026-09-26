///|
// Inventory includes setup dependencies because skipping a gate can also skip setup.
async fn gate_dossier(dossier : Json, push_runtime? : Bool = false) -> Json {
  let d = obj(dossier)
  let root = str(d["root"])
  let policy = obj(read_json(root + "/verification.json"))
  let sections : Map[String, String] = Map([])
  let mut current = ""
  for raw in @fs.read_file(root + "/mise.toml").text().split("\n") {
    let line = raw.trim().to_owned()
    if line.has_prefix("[") {
      current = if line.has_prefix("[tasks.") && line.has_suffix("]") {
        let key = line[7:line.length() - 1].to_owned()
        if key.has_prefix("\"") && key.has_suffix("\"") {
          key[1:key.length() - 1].to_owned()
        } else {
          key
        }
      } else {
        ""
      }
    }
    if current != "" {
      sections[current] = sections.get(current).unwrap_or("") +
        raw.to_owned() +
        "\n"
    }
  }
  let tests : Array[Json] = []
  for name_json in arr(policy["full_gate_tasks"]) {
    let name = str(name_json)
    if push_runtime && (name == "verify" || name == "verify-native") {
      continue
    }
    let pending = [name]
    let visited : Map[String, Bool] = Map([])
    let descriptions : Array[String] = []
    let mut i = 0
    while i < pending.length() {
      let key = pending[i]
      i += 1
      if visited.contains(key) {
        continue
      }
      visited[key] = true
      assert_true(
        sections.contains(key),
        msg="missing gate or dependency definition",
      )
      let definition = sections[key]
      descriptions.push(definition)
      for raw in definition.split("\n") {
        let line = raw.trim().to_owned()
        if line.has_prefix("depends = ") {
          for dep in arr(@json.parse(line[10:].to_owned())) {
            pending.push(str(dep))
          }
        }
        if line.contains("mise run ") {
          for word in line.split(" ") {
            let token = word
              .to_owned()
              .replace_all(old="'", new="")
              .replace_all(old="\"", new="")
            if sections.contains(token) {
              pending.push(token)
            }
          }
        }
      }
    }
    tests.push({
      "id": Json::string("gate:" + name),
      "name": Json::string("Metonic verification gate " + name),
      "file": Json::string("mise.toml:" + name),
      "package": "integration-gates",
      "index": "0",
      "symbols": Json::array(pending.map(Json::string)),
      "test_body": Json::string(descriptions.join("\n")),
      "source_file_text": Json::null(),
      "kind": "integration-gate",
      "command": ["mise", "run", name_json],
    })
  }
  if push_runtime {
    for
      file in [
        "scripts/verify-window-fixture-exclusion.mbtx", "scripts/verify-window-production-exclusion.mbtx",
      ] {
      tests.push({
        "id": Json::string("hook-extra:" + file),
        "name": Json::string(file),
        "file": Json::string(file),
        "package": "integration-gates",
        "index": "0",
        "kind": "hook-verification",
        "symbols": [],
        "test_body": Json::string("Hook invokes: " + file),
        "command": [".tools/moonbit/bin/moon.exe", "run", Json::string(file)],
      })
    }
    d["scope"] = "pre-push runtime checks only; excludes remaining root package tests"
  }
  d["tests"] = Json::array(tests)
  d["kind"] = "integration-gates"
  // This is a reviewable gate proposal, never a moon test -i plan.
  d["gate_definitions"] = Json::object(
    sections.map(fn(_, v) { Json::string(v) }),
  )
  d["force_all"] = Json::boolean(
    d.get("force_all") == Some(Json::boolean(true)) ||
    arr(d["changed"]).any(p => {
      p == Json::string("mise.toml") || p == Json::string("verification.json")
    }),
  )
  Json::object(d)
}
