///|
async test "staged records bind the new tree and reject changed or hidden inputs" {
  let directory = @fs.tmpdir(prefix="metonic-index-record")
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
  @fs.write_file(directory + "/input.mbt", "staged content")
  ignore(git(["add", "input.mbt"]))
  let tree = git(["write-tree"])
  require_index_tree(directory, tree)
  let config_file = directory + "-config.json"
  let record_file = directory + "-record.json"
  let invocation : Json = ["git", "diff", "--quiet"]
  let config : Json = {
    "files": [directory + "/input.mbt"],
    "context": {
      "target": "fixture",
      "toolchain": "fixture",
      "policy": "fixture",
      "command": invocation.stringify(),
      "tree": tree,
      "checkout": @fs.realpath(directory),
      "base_commit": "unborn",
    },
  }
  @fs.write_file(config_file, config.stringify())
  record_checkout(
    directory,
    tree,
    config_file,
    record_file,
    "git",
    ["diff", "--quiet"],
    staged=true,
  )
  assert_true(matching_record(config_file, record_file))
  ignore(
    git([
      "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "-c",
      "commit.gpgsign=false", "-c", "core.hooksPath=disabled-hooks", "commit", "--quiet",
      "-m", "verified staged tree",
    ]),
  )
  require_checkout_tree(directory, tree)
  assert_true(matching_record(config_file, record_file))
  let updated : Map[String, Json] = @json.from_json(config)
  let updated_context : Map[String, Json] = @json.from_json(updated["context"])
  updated_context["base_commit"] = Json::string(comparison_head(directory))
  updated["context"] = Json::object(updated_context)
  @fs.write_file(config_file, Json::object(updated).stringify())
  for mode in ["unstaged", "untracked", "hidden", "different-index"] {
    if mode == "unstaged" {
      @fs.write_file(directory + "/input.mbt", "changed")
    }
    if mode == "untracked" {
      @fs.write_file(directory + "/extra.mbt", "new")
    }
    if mode == "hidden" {
      ignore(git(["update-index", "--assume-unchanged", "input.mbt"]))
    }
    if mode == "different-index" {
      ignore(git(["read-tree", "--empty"]))
    }
    let rejected = try {
      record_checkout(
        directory,
        tree,
        config_file,
        record_file,
        "git",
        ["diff", "--quiet"],
        staged=true,
      )
      false
    } catch {
      _ => true
    }
    assert_true(rejected, msg=mode)
    assert_false(matching_record(config_file, record_file))
    if mode == "untracked" {
      @fs.remove(directory + "/extra.mbt")
    }
    if mode == "hidden" {
      ignore(git(["update-index", "--no-assume-unchanged", "input.mbt"]))
    }
    @fs.write_file(directory + "/input.mbt", "staged content")
    ignore(git(["add", "input.mbt"]))
  }
  let settings : Map[String, Json] = @json.from_json(
    @json.parse(@fs.read_file(config_file).text()),
  )
  let context : Map[String, Json] = @json.from_json(settings["context"])
  let changing : Json = ["git", "read-tree", "--empty"]
  context["command"] = Json::string(changing.stringify())
  settings["context"] = Json::object(context)
  @fs.write_file(config_file, Json::object(settings).stringify())
  let rejected = try {
    record_checkout(
      directory,
      tree,
      config_file,
      record_file,
      "git",
      ["read-tree", "--empty"],
      staged=true,
    )
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_false(matching_record(config_file, record_file))
  ignore(git(["add", "input.mbt"]))
  let change_head : Json = [
    "git", "symbolic-ref", "HEAD", "refs/heads/changed-base",
  ]
  context["command"] = Json::string(change_head.stringify())
  settings["context"] = Json::object(context)
  @fs.write_file(config_file, Json::object(settings).stringify())
  let rejected_head = try {
    record_checkout(
      directory,
      tree,
      config_file,
      record_file,
      "git",
      ["symbolic-ref", "HEAD", "refs/heads/changed-base"],
      staged=true,
    )
    false
  } catch {
    _ => true
  }
  assert_true(rejected_head)
  assert_eq(comparison_head(directory), "unborn")
  assert_false(matching_record(config_file, record_file))
}
