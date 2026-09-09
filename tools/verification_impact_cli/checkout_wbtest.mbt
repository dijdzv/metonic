///|
async test "push checkout rejects other trees and all visible local changes" {
  let prefix = ".work/push-checkout-test-"
  let mut index = 0
  while @fs.exists(prefix + index.to_string()) {
    index += 1
  }
  let directory = prefix + index.to_string()
  @fs.mkdir(directory, recursive=true)
  let git = async fn(args : Array[String]) {
    let (code, output, _) = @process.collect_output(
      "git",
      ["-C", directory] + args,
      no_console_window=true,
    )
    assert_eq(code, 0)
    output.text().trim().to_owned()
  }
  ignore(git(["init", "--quiet"]))
  @fs.write_file(directory + "/input.mbt", "first")
  ignore(git(["add", "input.mbt"]))
  ignore(
    git([
      "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "-c",
      "commit.gpgsign=false", "-c", "core.hooksPath=disabled-hooks", "commit", "--quiet",
      "-m", "fixture",
    ]),
  )
  let tree = git(["rev-parse", "HEAD^{tree}"])
  let commit = git(["rev-parse", "HEAD"])
  let zero = "0000000000000000000000000000000000000000"
  let updates = "HEAD " +
    commit +
    " refs/heads/one " +
    zero +
    "\nHEAD " +
    commit +
    " refs/heads/two " +
    zero
  run_push_checkout(directory, updates, "git", [
    "config", "--add", "fixture.runs", "once",
  ])
  assert_eq(git(["config", "--get-all", "fixture.runs"]), "once")
  run_push_checkout(
    directory,
    "(delete) " + zero + " refs/heads/old " + commit,
    "missing-command-must-not-run",
    [],
  )
  require_checkout_tree(directory, tree)
  let rejects = async fn(expected : String) {
    let rejected = try {
      require_checkout_tree(directory, expected)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  rejects("0000000000000000000000000000000000000000")
  @fs.write_file(directory + "/input.mbt", "changed")
  rejects(tree)
  ignore(git(["add", "input.mbt"]))
  rejects(tree)
  ignore(git(["restore", "--staged", "--worktree", "input.mbt"]))
  @fs.write_file(directory + "/untracked.mbt", "new test")
  rejects(tree)
  @fs.remove(directory + "/untracked.mbt")
  require_checkout_tree(directory, tree)
  for
    flags in [
      ("--assume-unchanged", "--no-assume-unchanged"),
      ("--skip-worktree", "--no-skip-worktree"),
    ] {
    let (enable, disable) = flags
    ignore(git(["update-index", enable, "input.mbt"]))
    rejects(tree)
    @fs.write_file(directory + "/input.mbt", "hidden change")
    rejects(tree)
    ignore(git(["update-index", disable, "input.mbt"]))
    ignore(git(["restore", "input.mbt"]))
    require_checkout_tree(directory, tree)
  }
  run_checkout(directory, tree, "git", ["diff", "--quiet"])
  for
    command in [
      ["rev-parse", "--verify", "refs/heads/missing-fixture-ref"],
      ["read-tree", "--empty"],
    ] {
    let rejected = try {
      run_checkout(directory, tree, "git", command)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  ignore(git(["reset", "--quiet", "HEAD"]))
  require_checkout_tree(directory, tree)
  let config_file = directory + "-config.json"
  let record_file = directory + "-record.json"
  let command : Json = ["git", "diff", "--quiet"]
  let config : Json = {
    "files": [@fs.realpath(directory + "/input.mbt")],
    "context": {
      "target": "fixture",
      "toolchain": "fixture",
      "policy": "fixture",
      "command": command.stringify(),
      "tree": tree,
      "checkout": @fs.realpath(directory),
    },
  }
  @fs.write_file(config_file, config.stringify())
  record_checkout(directory, tree, config_file, record_file, "git", [
    "diff", "--quiet",
  ])
  assert_true(matching_record(config_file, record_file))
  let rejected_record = try {
    record_checkout(directory, tree, config_file, record_file, "git", [
      "read-tree", "--empty",
    ])
    false
  } catch {
    _ => true
  }
  assert_true(rejected_record)
  assert_false(matching_record(config_file, record_file))
  require_checkout_tree(directory, tree)
  for
    arguments in [
      ["rev-parse", "--verify", "refs/heads/missing-fixture-ref"],
      ["read-tree", "--empty"],
    ] {
    let invocation : Json = Json::array((["git"] + arguments).map(Json::string))
    let failed_config : Json = {
      "files": [@fs.realpath(directory + "/input.mbt")],
      "context": {
        "target": "fixture",
        "toolchain": "fixture",
        "policy": "fixture",
        "command": invocation.stringify(),
        "tree": tree,
        "checkout": @fs.realpath(directory),
      },
    }
    @fs.write_file(config_file, failed_config.stringify())
    let rejected_execution = try {
      record_checkout(
        directory, tree, config_file, record_file, "git", arguments,
      )
      false
    } catch {
      _ => true
    }
    assert_true(rejected_execution)
    assert_false(matching_record(config_file, record_file))
    assert_false(@fs.exists(record_file + ".lock"))
    ignore(git(["reset", "--quiet", "HEAD"]))
  }
  @fs.write_file(directory + "/input.mbt", "second tree")
  ignore(git(["add", "input.mbt"]))
  ignore(
    git([
      "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "-c",
      "commit.gpgsign=false", "-c", "core.hooksPath=disabled-hooks", "commit", "--quiet",
      "-m", "second fixture",
    ]),
  )
  let current = git(["rev-parse", "HEAD"])
  let mixed = "HEAD " + current + " refs/heads/current " + zero + "\n" + updates
  let rejected_mixed = try {
    run_push_checkout(directory, mixed, "git", [
      "config", "--add", "fixture.runs", "unexpected",
    ])
    false
  } catch {
    _ => true
  }
  assert_true(rejected_mixed)
  assert_eq(git(["config", "--get-all", "fixture.runs"]), "once")
}
