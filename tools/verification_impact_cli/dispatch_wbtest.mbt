///|
async test "push dispatch reuses only matching commit input and falls back otherwise" {
  let directory = @fs.tmpdir(prefix="metonic-push-dispatch")
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
  ignore(git(["add", "."]))
  ignore(
    git([
      "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "-c",
      "commit.gpgsign=false", "-c", "core.hooksPath=disabled-hooks", "commit", "--quiet",
      "-m", "fixture",
    ]),
  )
  let head = git(["rev-parse", "HEAD"])
  let tree = git(["rev-parse", "HEAD^{tree}"])
  let zero = "0000000000000000000000000000000000000000"
  let input = "HEAD " + head + " refs/heads/test " + zero
  let config_file = directory + "-config.json"
  let record_file = directory + "-record.json"
  let dependency = directory + "-dependency.txt"
  @fs.write_file(dependency, "original")
  let commit_command = ["git", "diff", "--quiet"]
  let invocation : Json = Json::array(commit_command.map(Json::string))
  let config : Json = {
    "files": [directory + "/input.mbt", dependency],
    "context": {
      "target": "fixture",
      "toolchain": "fixture",
      "policy": "fixture",
      "tree": tree,
      "checkout": @fs.realpath(directory),
      "base_commit": head,
      "command": invocation.stringify(),
    },
  }
  @fs.write_file(config_file, config.stringify())
  let full = ["git", "config", "--add", "fixture.runs", "full"]
  let remainder = ["git", "config", "--add", "fixture.runs"]
  let collector = directory + "-discover.mbtx"
  @fs.write_file(
    collector, "import {\n  \"moonbitlang/async@0.21.2\",\n  \"moonbitlang/async@0.21.2/fs\",\n  \"moonbitlang/core/env\",\n}\nasync fn main {\n let args = @env.args()\n @fs.write_file(args[2], @fs.read_file(args[1]).text())\n}\n",
  )
  let discover = [
    @fs.realpath(".tools/moonbit/bin/moon.exe"),
    "run",
    collector,
    "--",
    config_file,
  ]
  let fresh_dispatch = async fn() {
    run_discovered_push(
      directory, input, record_file, discover, commit_command, full, remainder,
    )
  }
  let dispatch = async fn(commands : Array[String]) {
    run_recorded_push(
      directory, input, config_file, record_file, commands, full, remainder,
    )
  }
  dispatch(commit_command)
  assert_eq(git(["config", "--get-all", "fixture.runs"]), "full")
  ignore(git(["config", "--unset-all", "fixture.runs"]))
  record_checkout(directory, tree, config_file, record_file, "git", [
    "diff", "--quiet",
  ])
  dispatch(commit_command)
  assert_eq(git(["config", "--get-all", "fixture.runs"]), head)
  ignore(git(["config", "--unset-all", "fixture.runs"]))
  fresh_dispatch()
  assert_eq(git(["config", "--get-all", "fixture.runs"]), head)
  ignore(git(["config", "--unset-all", "fixture.runs"]))
  dispatch(["git", "status"])
  assert_eq(git(["config", "--get-all", "fixture.runs"]), "full")
  ignore(git(["config", "--unset-all", "fixture.runs"]))
  @fs.write_file(dependency, "changed")
  fresh_dispatch()
  assert_eq(git(["config", "--get-all", "fixture.runs"]), "full")
  ignore(git(["config", "--unset-all", "fixture.runs"]))
  dispatch(commit_command)
  assert_eq(git(["config", "--get-all", "fixture.runs"]), "full")
  ignore(git(["config", "--unset-all", "fixture.runs"]))
  let unrelated = git([
    "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit-tree",
    tree, "-m", "unrelated root",
  ])
  for base in ["unborn", "HEAD", unrelated] {
    let altered : Map[String, Json] = @json.from_json(config)
    let context : Map[String, Json] = @json.from_json(altered["context"])
    context["base_commit"] = Json::string(base)
    altered["context"] = Json::object(context)
    @fs.write_file(config_file, Json::object(altered).stringify())
    record_checkout(directory, tree, config_file, record_file, "git", [
      "diff", "--quiet",
    ])
    dispatch(commit_command)
    assert_eq(git(["config", "--get-all", "fixture.runs"]), "full", msg=base)
    ignore(git(["config", "--unset-all", "fixture.runs"]))
  }
  run_recorded_push(
    directory,
    "(delete) " + zero + " refs/heads/test " + head,
    "missing-config",
    "missing-record",
    commit_command,
    ["must-not-execute"],
    remainder,
  )
  @fs.write_file(directory + "/input.mbt", "dirty")
  let rejected = try {
    dispatch(commit_command)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  let (code, _, _) = @process.collect_output(
    "git",
    ["-C", directory, "config", "--get-all", "fixture.runs"],
    no_console_window=true,
  )
  assert_eq(code, 1)
}
