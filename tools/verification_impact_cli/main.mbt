///|
async fn main {
  let args = @env.args()
  assert_true(
    args.length() >= 2,
    msg="usage: verification_impact_cli packages.json [--metadata packages.json] [absolute changed paths...]",
  )
  if args[1] == "--plan" {
    assert_true(args.length() >= 3, msg="expected plan configuration filename")
    let config : Map[String, Json] = @json.from_json(
      @json.parse(@fs.read_file(args[2]).text()),
    )
    let modules : Map[String, String] = @json.from_json(
      config.get("modules").unwrap(),
    )
    let filenames : Array[String] = @json.from_json(
      config.get("graphs").unwrap(),
    )
    let graphs : Array[Array[@impact.ExportedPackage]] = []
    let owned : Map[String, String] = Map([])
    let matched_modules : Map[String, Bool] = Map([])
    for filename in filenames {
      let graph = @impact.read_package_graph(@fs.read_file(filename).text())
      for pkg in graph {
        let mut matched = false
        for module_name, directory in modules {
          if pkg.name == module_name || pkg.name.has_prefix(module_name + "/") {
            assert_false(matched, msg="overlapping module mappings")
            matched = true
            matched_modules[module_name] = true
            let suffix = pkg.name[module_name.length():].to_owned()
            assert_false(
              suffix.split("/").any(part => part == ".." || part == "."),
            )
            let directory = @fs.realpath(directory + suffix)
            assert_true(
              @fs.exists(directory + "/moon.pkg") ||
              @fs.exists(directory + "/moon.pkg.json"),
              msg="mapped package manifest missing",
            )
            match owned.get(pkg.name) {
              Some(existing) => assert_eq(existing, directory)
              None => owned[pkg.name] = directory
            }
          }
        }
      }
      graphs.push(graph)
    }
    for module_name, _ in modules {
      assert_true(
        matched_modules.contains(module_name),
        msg="configured module missing from supplied graphs: " + module_name,
      )
    }
    let changes = args[3:].to_owned()
    let result = @impact.select_exported(graphs, owned, changes)
    let output : Json = { "full": result.full, "packages": result.packages }
    println(output.stringify())
    return
  }
  if args[1] == "--read-export" {
    assert_eq(args.length(), 3, msg="expected one package_graph.dot filename")
    let packages = @impact.read_package_graph(@fs.read_file(args[2]).text())
    let output : Json = Json::array(
      packages.map(pkg => { "name": pkg.name, "dependencies": pkg.dependencies }),
    )
    println(output.stringify())
    return
  }
  let metadata = [@json.parse(@fs.read_file(args[1]).text())]
  let changes : Array[String] = []
  let mut i = 2
  while i < args.length() {
    if args[i] == "--metadata" {
      i = i + 1
      assert_true(i < args.length(), msg="missing metadata filename")
      metadata.push(@json.parse(@fs.read_file(args[i]).text()))
    } else {
      changes.push(args[i])
    }
    i = i + 1
  }
  let result = @impact.select_many(metadata, changes)
  let output : Json = { "full": result.full, "packages": result.packages }
  println(output.stringify())
}
