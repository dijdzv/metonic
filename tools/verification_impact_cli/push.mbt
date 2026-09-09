///|
async fn resolve_push(input : String, directory? : String = ".") -> Json {
  let updates = @impact.read_push_updates(input)
  let result : Array[Json] = []
  for update in updates {
    match update.local_oid {
      None => result.push({ "ref": update.remote_ref, "deleted": true })
      Some(oid) => {
        let resolved : Array[String] = []
        for kind in ["commit", "tree"] {
          let (code, output, _) = @process.collect_output(
            "git",
            ["-C", directory, "rev-parse", "--verify", oid + "^{" + kind + "}"],
            no_console_window=true,
          )
          assert_eq(
            code,
            0,
            msg="push object must resolve to a local commit and tree",
          )
          let value = output.text().trim().to_owned()
          assert_false(
            value.is_empty() || value.contains("\n"),
            msg="unexpected Git revision output",
          )
          resolved.push(value)
        }
        result.push({
          "ref": update.remote_ref,
          "deleted": false,
          "commit": resolved[0],
          "tree": resolved[1],
        })
      }
    }
  }
  Json::array(result)
}

///|
async fn run_push_checkout(
  directory : String,
  input : String,
  command : String,
  arguments : Array[String],
) -> Unit {
  let updates : Array[Map[String, Json]] = @json.from_json(
    resolve_push(input, directory~),
  )
  let mut tree : String? = None
  for update in updates {
    if update.get("deleted") == Some(Json::boolean(true)) {
      continue
    }
    let expected : String = @json.from_json(update.get("tree").unwrap())
    require_checkout_tree(directory, expected)
    tree = Some(expected)
  }
  if tree is Some(expected) {
    run_checkout(directory, expected, command, arguments)
  }
}

///|
async fn read_push_input(filename : String) -> String {
  if filename != "-" {
    return @fs.read_file(filename).text()
  }
  let buffer = Buffer()
  while @stdio.stdin.read_some(max_len=4096) is Some(chunk) {
    buffer.write_bytes(chunk)
    assert_true(buffer.length() <= 1048576, msg="pre-push input exceeds 1 MiB")
  }
  @utf8.decode(buffer.to_bytes())
}

///|
async fn require_checkout_tree(
  directory : String,
  expected_tree : String,
) -> Unit {
  let (tree_code, tree_output, _) = @process.collect_output(
    "git",
    ["-C", directory, "rev-parse", "--verify", "HEAD^{tree}"],
    no_console_window=true,
  )
  assert_eq(tree_code, 0, msg="verification checkout has no committed tree")
  assert_eq(
    tree_output.text().trim().to_owned(),
    expected_tree,
    msg="verification checkout does not match the pushed tree",
  )
  let (index_code, index_output, _) = @process.collect_output(
    "git",
    ["-C", directory, "ls-files", "-v", "-z"],
    no_console_window=true,
  )
  assert_eq(index_code, 0, msg="cannot inspect verification index flags")
  for entry in index_output.text().split("\u0000") {
    assert_true(
      entry.is_empty() || entry.has_prefix("H "),
      msg="verification requires ordinary tracked entries without assume-unchanged or skip-worktree",
    )
  }
  let (status_code, status_output, _) = @process.collect_output(
    "git",
    [
      "-C", directory, "status", "--porcelain=v1", "--untracked-files=all", "--ignore-submodules=none",
    ],
    no_console_window=true,
  )
  assert_eq(status_code, 0, msg="cannot inspect verification checkout")
  assert_true(
    status_output.text().is_empty(),
    msg="verification checkout contains staged, unstaged or untracked changes",
  )
}

///|
async fn run_checkout(
  directory : String,
  expected_tree : String,
  command : String,
  arguments : Array[String],
) -> Unit {
  require_checkout_tree(directory, expected_tree)
  let code = @process.run(
    command,
    arguments,
    cwd=directory,
    no_console_window=true,
  )
  require_checkout_tree(directory, expected_tree)
  assert_eq(code, 0, msg="checkout verification failed")
}

///|
async fn record_checkout(
  directory : String,
  expected_tree : String,
  config_file : String,
  record : String,
  command : String,
  arguments : Array[String],
) -> Unit {
  record_verification(config_file, record, () => {
    let config : Map[String, Json] = @json.from_json(
      @json.parse(@fs.read_file(config_file).text()),
    )
    let context : Map[String, String] = @json.from_json(
      config.get("context").unwrap(),
    )
    let invocation : Json = Json::array(
      ([command] + arguments).map(Json::string),
    )
    assert_eq(context.get("command"), Some(invocation.stringify()))
    assert_eq(context.get("tree"), Some(expected_tree))
    assert_eq(context.get("checkout"), Some(@fs.realpath(directory)))
    run_checkout(directory, expected_tree, command, arguments)
  })
}
