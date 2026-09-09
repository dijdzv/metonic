///|
pub struct SourceInputs {
  files : Array[String]
  packages : Array[String]
} derive(Debug, Eq)

///|
pub fn source_inputs(
  metadata : Array[Json],
  destinations : Array[String],
) -> SourceInputs raise {
  let graphs : Array[Array[ExportedPackage]] = []
  let targets = destinations.map(path)
  let sources : Map[String, Array[String]] = Map([])
  for document in metadata {
    ignore(parse(document))
    let graph : Array[ExportedPackage] = []
    let entries : Array[Json] = @json.from_json(field(document, "packages"))
    for entry in entries {
      let directory = path(@json.from_json(field(entry, "root-path")))
      let selected = targets.contains(directory)
      let dependencies : Array[String] = []
      let dependency_keys = if selected {
        ["deps", "test-deps", "wbtest-deps"]
      } else {
        ["deps"]
      }
      for key in dependency_keys {
        let deps : Array[Json] = @json.from_json(field(entry, key))
        for dep in deps {
          dependencies.push(path(@json.from_json(field(dep, "fspath"))))
        }
      }
      graph.push({ name: directory, dependencies, })
      let files = sources.get_or_default(directory, [])
      let source_keys = if selected {
        ["files", "test-files", "wbtest-files", "mbt-md-files"]
      } else {
        ["files"]
      }
      for key in source_keys {
        let listed : Map[String, Json] = @json.from_json(field(entry, key))
        for filename, _ in listed {
          let filename = path(filename)
          if !files.contains(filename) {
            files.push(filename)
          }
        }
      }
      sources[directory] = files
    }
    graphs.push(graph)
  }
  let required = dependency_inputs(graphs, targets)
  let files : Array[String] = []
  for directory in required {
    for filename in sources[directory] {
      if !files.contains(filename) {
        files.push(filename)
      }
    }
  }
  files.sort()
  { files, packages: required, }
}
