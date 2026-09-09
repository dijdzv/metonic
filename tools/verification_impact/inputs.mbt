///|
pub fn dependency_inputs(
  graphs : Array[Array[ExportedPackage]],
  destinations : Array[String],
) -> Array[String] raise {
  assert_false(graphs.is_empty(), msg="missing dependency graphs")
  let dependencies : Map[String, Array[String]] = Map([])
  for graph in graphs {
    assert_false(graph.is_empty(), msg="empty dependency graph")
    for pkg in graph {
      let merged = dependencies.get_or_default(pkg.name, [])
      for dep in pkg.dependencies {
        if !merged.contains(dep) {
          merged.push(dep)
        }
      }
      dependencies[pkg.name] = merged
    }
  }
  let inputs : Map[String, Bool] = Map([])
  let pending = destinations.copy()
  while pending.pop() is Some(name) {
    if inputs.contains(name) {
      continue
    }
    guard dependencies.get(name) is Some(deps) else {
      fail("missing verification input package: " + name)
    }
    inputs[name] = true
    for dep in deps {
      pending.push(dep)
    }
  }
  let names = inputs.keys().collect()
  names.sort()
  names
}
