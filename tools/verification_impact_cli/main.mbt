///|
async fn main {
  let args = @env.args()
  assert_true(
    args.length() >= 2,
    msg="usage: verification_impact_cli packages.json [--metadata packages.json] [absolute changed paths...]",
  )
  if args[1] == "--run-push-checkout" {
    assert_true(
      args.length() >= 5,
      msg="usage: --run-push-checkout directory input command [args...]",
    )
    run_push_checkout(
      args[2],
      read_push_input(args[3]),
      args[4],
      args[5:].to_owned(),
    )
    return
  }
  if args[1] == "--partition-metadata" || args[1] == "--partition-workspace" {
    let scoped = args[1] == "--partition-workspace"
    let start = if scoped { 6 } else { 5 }
    assert_true(
      args.length() >= start,
      msg="usage: --partition-metadata policy target metadata [changes...] | --partition-workspace policy target metadata absolute-scope [changes...]",
    )
    let (commit, push) = @impact.partition_metadata(
      @json.parse(@fs.read_file(args[2]).text()),
      args[3],
      @json.parse(@fs.read_file(args[4]).text()),
      args[start:].to_owned(),
      scope?=if scoped { Some(args[5]) } else { None },
    )
    let output : Json = { "pre_commit": commit, "pre_push": push }
    println(output.stringify())
    return
  }
  if args[1] == "--partition-tests" {
    assert_eq(
      args.length(),
      5,
      msg="usage: --partition-tests policy target inventory",
    )
    let policy = @json.parse(@fs.read_file(args[2]).text())
    let inventory : Map[String, Json] = @json.from_json(
      @json.parse(@fs.read_file(args[4]).text()),
    )
    let available : Array[String] = @json.from_json(
      inventory.get("available").unwrap(),
    )
    let affected : Array[String] = @json.from_json(
      inventory.get("affected").unwrap(),
    )
    let (commit, push) = @impact.partition_tests(
      policy,
      args[3],
      available,
      affected,
    )
    let output : Json = { "pre_commit": commit, "pre_push": push }
    println(output.stringify())
    return
  }
  if args[1] == "--record-checkout" || args[1] == "--record-index" {
    assert_true(
      args.length() >= 7,
      msg="usage: --record-checkout|--record-index directory expected-tree config record command [args...]",
    )
    record_checkout(
      args[2],
      args[3],
      args[4],
      args[5],
      args[6],
      args[7:].to_owned(),
      staged=args[1] == "--record-index",
    )
    return
  }
  if args[1] == "--run-checkout" {
    assert_true(
      args.length() >= 5,
      msg="usage: --run-checkout directory expected-tree command [args...]",
    )
    run_checkout(args[2], args[3], args[4], args[5:].to_owned())
    return
  }
  if args[1] == "--source-inputs" {
    assert_true(args.length() >= 4, msg="expected metadata and package paths")
    let metadata = [@json.parse(@fs.read_file(args[2]).text())]
    let mut start = 3
    while start < args.length() && args[start] == "--metadata" {
      assert_true(start + 1 < args.length(), msg="missing metadata filename")
      metadata.push(@json.parse(@fs.read_file(args[start + 1]).text()))
      start += 2
    }
    assert_true(start < args.length(), msg="missing package destinations")
    let inputs = @impact.source_inputs(metadata, args[start:].to_owned())
    let files = inputs.files
    for filename in source_manifests(inputs.packages) {
      if !files.contains(filename) {
        files.push(filename)
      }
    }
    files.sort()
    let output : Json = { "files": files, "packages": inputs.packages }
    println(output.stringify())
    return
  }
  if args[1] == "--match-record" {
    assert_eq(
      args.length(),
      4,
      msg="usage: --match-record config.json record.json",
    )
    let output : Json = { "matches": matching_record(args[2], args[3]) }
    println(output.stringify())
    return
  }
  if args[1] == "--record" {
    assert_true(
      args.length() >= 5,
      msg="usage: --record config.json record.json command [args...]",
    )
    let config : Map[String, Json] = @json.from_json(
      @json.parse(@fs.read_file(args[2]).text()),
    )
    let context : Map[String, String] = @json.from_json(
      config.get("context").unwrap(),
    )
    let command : Json = Json::array(args[4:].to_owned().map(Json::string))
    assert_eq(
      context.get("command"),
      Some(command.stringify()),
      msg="recorded command does not match execution",
    )
    record_verification(args[2], args[3], () => {
      let code = @process.run(
        args[4],
        args[5:].to_owned(),
        no_console_window=true,
      )
      assert_eq(code, 0, msg="verification command failed")
    })
    return
  }
  if args[1] == "--fingerprint" {
    assert_eq(
      args.length(),
      3,
      msg="expected fingerprint configuration filename",
    )
    println(fingerprint(args[2]).stringify())
    return
  }
  if args[1] == "--push-plan" {
    assert_eq(args.length(), 3, msg="expected pre-push input filename")
    let input = read_push_input(args[2])
    println(resolve_push(input).stringify())
    return
  }
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
