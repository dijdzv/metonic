///|
async fn fingerprint(config_file : String) -> Json {
  let config : Map[String, Json] = @json.from_json(
    @json.parse(@fs.read_file(config_file).text()),
  )
  let filenames : Array[String] = @json.from_json(config.get("files").unwrap())
  let trees : Array[String] = @json.from_json(
    config.get("trees").unwrap_or(Json::array([])),
  )
  let context : Map[String, String] = @json.from_json(
    config.get("context").unwrap(),
  )
  assert_false(
    filenames.is_empty() && trees.is_empty(),
    msg="verification input list is empty",
  )
  for required in ["target", "toolchain", "command", "policy"] {
    assert_false(
      context.get(required).unwrap_or("").is_empty(),
      msg="missing fingerprint context: " + required,
    )
  }
  let paths : Array[String] = []
  let directories : Array[String] = []
  let pending = trees.copy()
  while pending.pop() is Some(directory) {
    assert_true(
      @fs.kind(directory, follow_symlink=false) is @fs.Directory,
      msg="input tree must be a real directory",
    )
    let canonical = @fs.realpath(directory).replace_all(old="\\", new="/")
    if directories.contains(canonical) {
      continue
    }
    directories.push(canonical)
    for name in @fs.readdir(canonical, include_hidden=true) {
      let child = canonical + "/" + name
      match @fs.kind(child, follow_symlink=false) {
        @fs.Directory => pending.push(child)
        @fs.Regular => filenames.push(child)
        _ => fail("unsupported verification input: " + child)
      }
    }
  }
  directories.sort()
  for filename in filenames {
    let canonical = @fs.realpath(filename).replace_all(old="\\", new="/")
    if !paths.contains(canonical) {
      paths.push(canonical)
    }
  }
  paths.sort()
  let inputs : Array[Json] = []
  let mut offset = 0
  while offset < paths.length() {
    let arguments = ["hash-object", "--no-filters", "--"]
    let batch : Array[String] = []
    let mut argument_units = 64
    while offset < paths.length() {
      let filename = paths[offset]
      // Leave room for Windows argument quoting and the executable path.
      let cost = filename.length() * 2 + 3
      if !batch.is_empty() && argument_units + cost > 16000 {
        break
      }
      batch.push(filename)
      arguments.push(filename)
      argument_units = argument_units + cost
      offset = offset + 1
    }
    let (code, output, _) = @process.collect_output(
      "git",
      arguments,
      no_console_window=true,
    )
    assert_eq(code, 0, msg="failed to fingerprint verification input")
    let hashes = output.text().trim().split("\n").to_array()
    assert_eq(hashes.length(), batch.length(), msg="incomplete Git hash output")
    for index = 0; index < batch.length(); index = index + 1 {
      let hash = hashes[index].trim().to_owned()
      assert_true(
        hash.length() == 40 || hash.length() == 64,
        msg="unexpected Git hash",
      )
      inputs.push({ "path": batch[index], "blob": hash })
    }
  }
  let keys = context.keys().collect()
  keys.sort()
  let fields : Array[Json] = keys.map(key => {
    "name": key,
    "value": context[key],
  })
  let names : Array[String] = @json.from_json(
    config.get("environment").unwrap_or(Json::array([])),
  )
  names.sort()
  let environment : Array[Json] = []
  let seen : Map[String, Bool] = Map([])
  for name in names {
    assert_false(
      name.is_empty() || name.contains("=") || name.contains("\u0000"),
      msg="invalid environment input name",
    )
    if seen.contains(name) {
      continue
    }
    seen[name] = true
    let value : Json = match @env.get_env_var(name) {
      Some(value) => Json::string(value)
      None => Json::null()
    }
    let digest = @async.with_task_group(async fn(group) {
      let (stdin, writer) = @process.write_to_process()
      defer writer.close()
      group.spawn_bg(async fn() {
        writer.write(value.stringify())
        writer.close()
      })
      let (code, output, _) = @process.collect_output(
        "git",
        ["hash-object", "--stdin"],
        stdin~,
        no_console_window=true,
      )
      assert_eq(code, 0, msg="cannot fingerprint environment input")
      output.text().trim().to_owned()
    })
    environment.push({ "name": name, "blob": digest })
  }
  {
    "version": 3,
    "inputs": inputs,
    "directories": directories,
    "context": fields,
    "environment": environment,
  }
}
