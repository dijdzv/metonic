///|
pub struct ExportedPackage {
  name : String
  dependencies : Array[String]
} derive(Debug, Eq)

///|
pub fn select_exported(
  graphs : Array[Array[ExportedPackage]],
  owned_paths : Map[String, String],
  changes : Array[String],
) -> Selection raise {
  assert_false(
    graphs.is_empty() || owned_paths.is_empty(),
    msg="missing graph or ownership",
  )
  let dependencies : Map[String, Array[String]] = Map([])
  for graph in graphs {
    assert_false(graph.is_empty(), msg="empty graph")
    for pkg in graph {
      let deps = dependencies.get_or_default(pkg.name, [])
      for dep in pkg.dependencies {
        if !deps.contains(dep) {
          deps.push(dep)
        }
      }
      dependencies[pkg.name] = deps
    }
  }
  let paths : Map[String, String] = Map([])
  let destinations : Map[String, String] = Map([])
  for name, directory in owned_paths {
    assert_true(
      dependencies.contains(name),
      msg="owned package missing from graph",
    )
    let directory = path(directory)
    assert_false(
      destinations.contains(directory),
      msg="ambiguous package directory",
    )
    paths[name] = directory
    destinations[directory] = name
  }
  for _, deps in dependencies {
    for dep in deps {
      assert_true(dependencies.contains(dep), msg="missing dependency node")
    }
  }
  let selected : Map[String, Bool] = Map([])
  let mut full = false
  for changed in changes {
    let changed = path(changed)
    let mut owner : String? = None
    let mut length = 0
    for name, directory in paths {
      if changed.has_prefix(directory + "/") && directory.length() > length {
        owner = Some(name)
        length = directory.length()
      }
    }
    if ![".mbt", ".mbti", ".c", ".h"].any(suffix => changed.has_suffix(suffix)) {
      full = true
    }
    match owner {
      Some(name) => selected[name] = true
      None => full = true
    }
  }
  let mut grew = true
  while grew && !full {
    grew = false
    for name, deps in dependencies {
      if !selected.contains(name) && deps.any(dep => selected.contains(dep)) {
        selected[name] = true
        grew = true
      }
    }
  }
  let packages : Array[String] = []
  for name, directory in paths {
    if full || selected.contains(name) {
      packages.push(directory)
    }
  }
  packages.sort()
  { packages, full, }
}

///|
pub fn read_package_graph(source : String) -> Array[ExportedPackage] raise {
  let nodes : Map[String, String] = Map([])
  let names : Array[String] = []
  let edges : Array[(String, String)] = []
  let mut opened = false
  let mut closed = false
  for raw in source.split("\n") {
    let line = raw.trim().to_owned()
    if line.is_empty() {
      continue
    }
    assert_false(closed, msg="content after graph end")
    if !opened {
      assert_eq(line, "digraph DepRelationship {")
      opened = true
      continue
    }
    if line == "}" {
      closed = true
      continue
    }
    if line == "rankdir=TB;" ||
      line == "node [shape=box style=\"filled,rounded\"];" {
      continue
    }
    let parts = line.split("\"").map(part => part.to_owned()).collect()
    assert_eq(parts.length(), 7, msg="unsupported graph statement")
    assert_eq(parts[0], "")
    let id = parts[1]
    if parts[2] == " -> " {
      assert_eq(parts[4], " [label=")
      assert_eq(parts[6], "];")
      edges.push((id, parts[3]))
    } else {
      assert_eq(parts[2], " [label=")
      assert_eq(parts[4], " fillcolor=")
      assert_eq(parts[6], "];")
      let label = parts[3].split("\\n").map(part => part.to_owned()).collect()
      assert_true(label.length() >= 2, msg="missing package or test kind")
      let kind = label[label.length() - 1]
      assert_true(
        ["Source", "InlineTest", "WhiteboxTest", "BlackboxTest"].contains(kind),
      )
      assert_true(id.has_suffix("@" + kind), msg="node kind mismatch")
      let name = label[:label.length() - 1].to_owned().join("/")
      assert_false(
        name.is_empty() || name.contains("\\"),
        msg="unsupported package label",
      )
      assert_false(nodes.contains(id), msg="duplicate graph node")
      nodes[id] = name
      if !names.contains(name) {
        names.push(name)
      }
    }
  }
  assert_true(
    opened && closed && !nodes.is_empty(),
    msg="incomplete package graph",
  )
  let dependencies : Map[String, Array[String]] = Map([])
  for edge in edges {
    guard nodes.get(edge.0) is Some(owner) else { fail("unknown edge source") }
    guard nodes.get(edge.1) is Some(dependency) else {
      fail("unknown edge destination")
    }
    if owner != dependency {
      let deps = dependencies.get_or_default(owner, [])
      if !deps.contains(dependency) {
        deps.push(dependency)
      }
      dependencies[owner] = deps
    }
  }
  names.map(name => {
    name,
    dependencies: dependencies.get_or_default(name, []),
  })
}
