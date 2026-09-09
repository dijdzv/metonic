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
  for filename in paths {
    let (code, output, _) = @process.collect_output(
      "git",
      ["hash-object", "--no-filters", "--", filename],
      no_console_window=true,
    )
    assert_eq(code, 0, msg="failed to fingerprint verification input")
    let hash = output.text().trim().to_owned()
    assert_true(
      hash.length() == 40 || hash.length() == 64,
      msg="unexpected Git hash",
    )
    inputs.push({ "path": filename, "blob": hash })
  }
  let keys = context.keys().collect()
  keys.sort()
  let fields : Array[Json] = keys.map(key => {
    "name": key,
    "value": context[key],
  })
  {
    "version": 2,
    "inputs": inputs,
    "directories": directories,
    "context": fields,
  }
}
