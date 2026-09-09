///|
pub fn partition_tests(
  policy : Json,
  target : String,
  available : Array[String],
  affected : Array[String],
) -> (Array[String], Array[String]) raise {
  let settings : Map[String, Json] = @json.from_json(policy)
  assert_eq(settings.get("version"), Some(Json::number(1)))
  assert_true(["js", "wasm", "wasm-gc", "native"].contains(target))
  let critical : Map[String, Array[String]] = @json.from_json(
    settings.get("critical_packages").unwrap(),
  )
  let commit = affected.copy()
  for package_name in affected {
    assert_true(
      available.contains(package_name),
      msg="affected package missing from target inventory",
    )
  }
  for package_name, targets in critical {
    assert_false(targets.is_empty())
    for supported in targets {
      assert_true(["js", "wasm", "wasm-gc", "native"].contains(supported))
    }
    if targets.contains(target) {
      assert_true(
        available.contains(package_name),
        msg="critical package missing from target inventory",
      )
      commit.push(package_name)
    }
  }
  let before_commit : Array[String] = []
  let before_push : Array[String] = []
  for package_name in available {
    if commit.contains(package_name) {
      if !before_commit.contains(package_name) {
        before_commit.push(package_name)
      }
    } else if !before_push.contains(package_name) {
      before_push.push(package_name)
    }
  }
  (before_commit, before_push)
}

///|
pub fn partition_metadata(
  policy : Json,
  target : String,
  metadata : Json,
  changes : Array[String],
) -> (Array[String], Array[String]) raise {
  let backend = match target {
    "js" => "Js"
    "wasm" => "Wasm"
    "wasm-gc" => "WasmGC"
    "native" => "Native"
    _ => fail("unsupported verification target")
  }
  let root = path(@json.from_json(field(metadata, "source_dir"))) + "/"
  let selected = select(metadata, changes)
  let entries : Array[Json] = @json.from_json(field(metadata, "packages"))
  let available : Array[String] = []
  let affected : Array[String] = []
  for entry in entries {
    let third_party : Bool = @json.from_json(field(entry, "is-third-party"))
    if third_party {
      continue
    }
    let targets : Array[String] = @json.from_json(
      field(entry, "supported-targets"),
    )
    if !targets.contains(backend) {
      continue
    }
    let directory = path(@json.from_json(field(entry, "root-path")))
    assert_true(
      directory.has_prefix(root),
      msg="owned package outside metadata source root",
    )
    let relative = directory[root.length():].to_owned()
    available.push(relative)
    if selected.packages.contains(directory) {
      affected.push(relative)
    }
  }
  partition_tests(policy, target, available, affected)
}
