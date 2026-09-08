///|
suberror OuterCancellation derive(Debug)

///|
fn response(id : Int) -> String {
  let value : Json = {
    "id": id,
    "session_id": "failure-test",
    "protocol_version": 1,
    "error": "",
    "text": "",
    "semantic_revision": 0,
    "frames": 1,
    "task_status": 0,
  }
  value.stringify() + "\n"
}

///|
async test "attachment failures close the connection without requiring server exit" {
  @async.with_timeout(10000, () => {
    let directory = @fs.tmpdir(prefix="metonic-attach-failure")
    defer @fs.rmdir(directory)
    let path = directory + "/session.json"
    defer @fs.remove(path)
    let name = directory
      .replace_all(old="\\", new="/")
      .split("/")
      .last()
      .unwrap()
      .to_owned()
    let server = @pipe.WindowsPipe::listen(name)
    defer server.close()
    let metadata : Json = {
      "protocol_version": 1,
      "session_id": "failure-test",
      "pipe": server.path(),
    }
    @fs.write_file(path, metadata.stringify())
    for mode in ["malformed", "wrong-id", "timeout", "cancel"] {
      @async.with_task_group() <| group => {
        group.spawn_bg() <| () => {
          server.accept()
          assert_true(server.read_until("\n").unwrap().contains("capabilities"))
          server.write(response(1))
          assert_true(server.read_until("\n").unwrap().contains("snapshot"))
          if mode == "malformed" {
            server.write("not-json\n")
          } else if mode == "wrong-id" {
            server.write(response(999))
          }
          assert_eq(
            server.read_until("\n"),
            None,
            msg="failed client retained its connection",
          )
        }
        let client = @attach.connect(path)
        defer client.close()
        let problem = try {
          if mode == "cancel" {
            ignore(
              @async.with_timeout(50, error=OuterCancellation, () => {
                client.request("snapshot", Json::object({}))
              }),
            )
          } else {
            ignore(client.request("snapshot", Json::object({}), timeout_ms=50))
          }
          ""
        } catch {
          error => @debug.to_string(error)
        }
        assert_true(problem != "", msg=mode)
        if mode == "malformed" {
          assert_true(
            problem.contains("invalid native session response"),
            msg=problem,
          )
        } else if mode == "wrong-id" {
          assert_true(
            problem.contains("response identity mismatch"),
            msg=problem,
          )
        } else if mode == "cancel" {
          assert_eq(problem, "OuterCancellation")
        } else {
          assert_eq(problem, "TimeoutError")
        }
        let closed = try {
          ignore(client.request("snapshot", Json::object({})))
          false
        } catch {
          error => @debug.to_string(error).contains("connection closed or busy")
        }
        assert_true(closed, msg=mode)
      }
      server.disconnect()
    }
  })
}
