///|
async fn run_recorded_push(
  directory : String,
  input : String,
  config_file : String,
  record_file : String,
  commit_command : Array[String],
  full_command : Array[String],
  remainder_command : Array[String],
) -> Unit {
  assert_false(
    commit_command.is_empty() ||
    full_command.is_empty() ||
    remainder_command.is_empty(),
  )
  let updates : Array[Map[String, Json]] = @json.from_json(
    resolve_push(input, directory~),
  )
  let commits : Array[String] = []
  let mut tree : String? = None
  for update in updates {
    if update.get("deleted") == Some(Json::boolean(true)) {
      continue
    }
    let expected : String = @json.from_json(update.get("tree").unwrap())
    require_checkout_tree(directory, expected)
    tree = Some(expected)
    commits.push(@json.from_json(update.get("commit").unwrap()))
  }
  guard tree is Some(expected) else { return }
  let mut base : String? = None
  let before = if @fs.exists(config_file) {
    Some(fingerprint(config_file))
  } else {
    None
  }
  if @fs.exists(config_file) && matching_record(config_file, record_file) {
    let config : Map[String, Json] = @json.from_json(
      @json.parse(@fs.read_file(config_file).text()),
    )
    let context : Map[String, String] = @json.from_json(
      config.get("context").unwrap(),
    )
    let invocation : Json = Json::array(commit_command.map(Json::string))
    if context.get("tree") == Some(expected) &&
      context.get("checkout") == Some(@fs.realpath(directory)) &&
      context.get("command") == Some(invocation.stringify()) {
      if context.get("base_commit") is Some(candidate) && candidate != "unborn" {
        let (code, output, _) = @process.collect_output(
          "git",
          [
            "-C",
            directory,
            "rev-parse",
            "--verify",
            "--end-of-options",
            candidate + "^{commit}",
          ],
          no_console_window=true,
        )
        // Resolve names again: a moved ref must not redefine a saved comparison.
        if code == 0 && output.text().trim().to_owned() == candidate {
          let mut ancestor = true
          for commit in commits {
            let (status, _, _) = @process.collect_output(
              "git",
              [
                "-C", directory, "merge-base", "--is-ancestor", candidate, commit,
              ],
              no_console_window=true,
            )
            assert_true(
              status == 0 || status == 1,
              msg="cannot check verification base ancestry",
            )
            ancestor = ancestor && status == 0
          }
          if ancestor {
            base = Some(candidate)
          }
        }
      }
    }
  }
  match base {
    Some(base) => {
      run_checkout(
        directory,
        expected,
        remainder_command[0],
        remainder_command[1:].to_owned() + [base],
      )
      assert_eq(
        Some(fingerprint(config_file)),
        before,
        msg="push verification configuration changed",
      )
      assert_true(
        matching_record(config_file, record_file),
        msg="commit verification inputs changed during push verification",
      )
    }
    None =>
      run_checkout(
        directory,
        expected,
        full_command[0],
        full_command[1:].to_owned(),
      )
  }
}
