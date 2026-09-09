///|
fn saved_comparison_base(value : Json) -> String? {
  try {
    let record : Map[String, Json] = @json.from_json(value)
    guard record.get("success") == Some(Json::boolean(true)) else {
      return None
    }
    let fingerprint : Map[String, Json] = @json.from_json(record["fingerprint"])
    let context : Array[Map[String, String]] = @json.from_json(
      fingerprint["context"],
    )
    for field in context {
      if field.get("name") == Some("base_commit") {
        return field.get("value")
      }
    }
    None
  } catch {
    _ => None
  }
}

///|
async fn run_discovered_push(
  directory : String,
  input : String,
  record : String,
  discover : Array[String],
  commit : Array[String],
  full : Array[String],
  remainder : Array[String],
) -> Unit {
  assert_false(
    discover.is_empty() ||
    full.is_empty() ||
    commit.is_empty() ||
    remainder.is_empty(),
  )
  let updates : Array[Map[String, Json]] = @json.from_json(
    resolve_push(input, directory~),
  )
  let mut nonempty = false
  for update in updates {
    if update.get("deleted") != Some(Json::boolean(true)) {
      require_checkout_tree(directory, @json.from_json(update["tree"]))
      nonempty = true
    }
  }
  if !nonempty {
    return
  }
  let base = if @fs.exists(record) {
    let parsed = Some(@json.parse(@fs.read_file(record).text())) catch {
      _ => None
    }
    match parsed {
      Some(value) => saved_comparison_base(value)
      None => None
    }
  } else {
    None
  }
  guard base is Some(base) && base != "unborn" else {
    run_push_checkout(directory, input, full[0], full[1:].to_owned())
    return
  }
  let (status, resolved, _) = @process.collect_output(
    "git",
    [
      "-C",
      directory,
      "rev-parse",
      "--verify",
      "--end-of-options",
      base + "^{commit}",
    ],
    no_console_window=true,
  )
  if status != 0 || resolved.text().trim().to_owned() != base {
    run_push_checkout(directory, input, full[0], full[1:].to_owned())
    return
  }
  let temporary = @fs.tmpdir(prefix="metonic-push-inputs")
  defer @async.protect_from_cancel(() => @fs.rmdir(temporary, recursive=true))
  let collect = async fn(path : String) {
    let code = @process.run(
      discover[0],
      discover[1:].to_owned() + [path, base],
      cwd=directory,
      no_console_window=true,
    )
    assert_eq(code, 0, msg="push input discovery failed")
  }
  let before_file = temporary + "/before.json"
  let after_file = temporary + "/after.json"
  collect(before_file)
  let before = fingerprint(before_file)
  run_recorded_push(
    directory, input, before_file, record, commit, full, remainder,
  )
  collect(after_file)
  assert_eq(
    fingerprint(after_file),
    before,
    msg="push input discovery changed during verification",
  )
  for update in updates {
    if update.get("deleted") != Some(Json::boolean(true)) {
      require_checkout_tree(directory, @json.from_json(update["tree"]))
    }
  }
}

///|
async fn record_discovered_index(
  directory : String,
  record : String,
  discover : Array[String],
  command : Array[String],
) -> Unit {
  assert_false(discover.is_empty() || command.is_empty())
  let temporary = @fs.tmpdir(prefix="metonic-record-inputs")
  defer @async.protect_from_cancel(() => @fs.rmdir(temporary, recursive=true))
  let before_file = temporary + "/before.json"
  let after_file = temporary + "/after.json"
  let collect = async fn(output : String) {
    let code = @process.run(
      discover[0],
      discover[1:].to_owned() + [output],
      cwd=directory,
      no_console_window=true,
    )
    assert_eq(code, 0, msg="verification input discovery failed")
  }
  record_verification(
    before_file,
    record,
    () => {
      let config : Map[String, Json] = @json.from_json(
        @json.parse(@fs.read_file(before_file).text()),
      )
      let context : Map[String, String] = @json.from_json(config["context"])
      let invocation : Json = Json::array(command.map(Json::string))
      assert_eq(context.get("command"), Some(invocation.stringify()))
      assert_eq(context.get("checkout"), Some(@fs.realpath(directory)))
      let base = comparison_head(directory)
      assert_eq(context.get("base_commit"), Some(base))
      let tree = context.get("tree").unwrap()
      require_index_tree(directory, tree)
      let before = fingerprint(before_file)
      let code = @process.run(
        command[0],
        command[1:].to_owned(),
        cwd=directory,
        no_console_window=true,
      )
      assert_eq(code, 0, msg="commit lane failed")
      require_index_tree(directory, tree)
      assert_eq(comparison_head(directory), base)
      collect(after_file)
      assert_eq(
        fingerprint(after_file),
        before,
        msg="discovered verification inputs changed",
      )
      require_index_tree(directory, tree)
      assert_eq(comparison_head(directory), base)
    },
    prepare=() => collect(before_file),
  )
}
