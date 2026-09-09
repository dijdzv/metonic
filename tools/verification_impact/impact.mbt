///|
pub struct Selection {
  packages : Array[String]
  full : Bool
} derive(Debug, Eq)

///|
priv struct Package {
  path : String
  owned : Bool
  dependencies : Array[String]
}

///|
fn field(value : Json, name : String) -> Json raise {
  guard value is Json::Object(fields) else { fail("expected metadata object") }
  guard fields.get(name) is Some(result) else {
    fail("missing metadata field: " + name)
  }
  result
}

///|
fn path(value : String) -> String raise {
  let value = value
    .replace_all(old="\\", new="/")
    .trim_end(chars="/")
    .to_owned()
  assert_true(
    value.has_prefix("/") || (value.length() > 2 && value[1:3] == ":/"),
    msg="metadata path must be absolute",
  )
  assert_false(
    value.split("/").any(part => part == ".." || part == "."),
    msg="metadata path must be normalized",
  )
  if value.has_prefix("//") || value.contains(":/") {
    value.to_lower()
  } else {
    value
  }
}

///|
fn parse(metadata : Json) -> Array[Package] raise {
  let entries : Array[Json] = @json.from_json(field(metadata, "packages"))
  assert_false(entries.is_empty(), msg="empty package metadata")
  let packages : Array[Package] = []
  for entry in entries {
    let root : String = @json.from_json(field(entry, "root-path"))
    let third_party : Bool = @json.from_json(field(entry, "is-third-party"))
    let dependencies : Array[String] = []
    for key in ["deps", "test-deps", "wbtest-deps"] {
      let deps : Array[Json] = @json.from_json(field(entry, key))
      for dep in deps {
        dependencies.push(path(@json.from_json(field(dep, "fspath"))))
      }
    }
    let root = path(root)
    assert_false(
      packages.any(pkg => pkg.path == root),
      msg="duplicate package path",
    )
    packages.push({ path: root, owned: !third_party, dependencies, })
  }
  packages
}

///|
pub fn select(metadata : Json, changes : Array[String]) -> Selection raise {
  select_many([metadata], changes)
}

///|
pub fn select_many(
  metadata : Array[Json],
  changes : Array[String],
) -> Selection raise {
  assert_false(metadata.is_empty(), msg="no workspace metadata supplied")
  let packages : Array[Package] = []
  for graph in metadata {
    for incoming in parse(graph) {
      let mut merged = false
      for i = 0; i < packages.length(); i = i + 1 {
        let existing = packages[i]
        if existing.path == incoming.path {
          let dependencies = existing.dependencies.copy()
          for dependency in incoming.dependencies {
            if !dependencies.contains(dependency) {
              dependencies.push(dependency)
            }
          }
          packages[i] = {
            path: existing.path,
            owned: existing.owned || incoming.owned,
            dependencies,
          }
          merged = true
          break
        }
      }
      if !merged {
        packages.push(incoming)
      }
    }
  }
  let selected : Map[String, Bool] = Map([])
  let mut full = false
  for change in changes {
    let changed = path(change)
    if ![".mbt", ".mbti", ".c", ".h"].any(suffix => changed.has_suffix(suffix)) {
      full = true
      break
    }
    let mut owner : String? = None
    for pkg in packages {
      if changed.has_prefix(pkg.path + "/") &&
        pkg.path.length() > owner.unwrap_or("").length() {
        owner = Some(pkg.path)
      }
    }
    match owner {
      Some(value) => selected[value] = true
      None => {
        full = true
        break
      }
    }
  }
  let mut grew = true
  while grew && !full {
    grew = false
    for pkg in packages {
      if !selected.contains(pkg.path) &&
        pkg.dependencies.any(dep => selected.contains(dep)) {
        selected[pkg.path] = true
        grew = true
      }
    }
  }
  {
    packages: packages
    .filter(pkg => pkg.owned && (full || selected.contains(pkg.path)))
    .map(pkg => pkg.path),
    full,
  }
}
