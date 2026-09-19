///|
async test "runtime snapshot survives replacement of build output and is removed after use" {
  let source = @fs.tmpdir(prefix="metonic-demo-source-test")
  defer @async.protect_from_cancel(() => remove_runtime(source))
  for name in runtime_files {
    @fs.write_file(source + "/" + name, name)
  }
  let mut executable = ""
  with_runtime(source, async fn(path) {
    executable = path
    @fs.write_file(source + "/window_app.exe", "new build")
    assert_eq(@fs.read_file(path).text(), "window_app.exe")
    let directory = path[:path.length() - "/window_app.exe".length()].to_owned()
    for name in runtime_files {
      assert_eq(@fs.read_file(directory + "/" + name).text(), name)
    }
  })
  assert_false(@fs.exists(executable))
  assert_eq(@fs.read_file(source + "/window_app.exe").text(), "new build")
}

///|
async test "failed runtime callback cleans staged files while preserving the original error" {
  let source = @fs.tmpdir(prefix="metonic-demo-failure-test")
  defer @async.protect_from_cancel(() => remove_runtime(source))
  for name in runtime_files {
    @fs.write_file(source + "/" + name, name)
  }
  let mut executable = ""
  let mut rejected = false
  with_runtime(source, path => {
    executable = path
    raise DemoFailure::Failure("test startup failed")
  }) catch {
    DemoFailure::Failure(message) => rejected = message == "test startup failed"
    error => raise error
  }
  assert_true(rejected)
  assert_false(@fs.exists(executable))
}

///|
async test "a running staged Windows image does not lock its build source" {
  let source = @fs.tmpdir(prefix="metonic-demo-image-test")
  defer @async.protect_from_cancel(() => remove_runtime(source))
  for name in runtime_files {
    @fs.write_file(source + "/" + name, name)
  }
  @fs.write_file(
    source + "/window_app.exe",
    @fs.read_file(".tools/moonbit/bin/moonrun.exe"),
  )
  with_runtime(source, async fn(executable) {
    let (reader, output) = @process.read_from_process()
    defer reader.close()
    defer output.close()
    @async.with_timeout(5000, () => {
      @async.with_task_group(async fn(group) {
        let child = @process.spawn(
          group,
          executable,
          fixture("server-ready"),
          stdout=output,
          no_console_window=true,
          cancel_handler=@process.hard_cancel(),
        )
        defer child.cancel()
        let ready = b"http://127.0.0.1:4173/\n"
        assert_eq(reader.read_exactly(ready.length()), ready)
        @fs.write_file(source + "/window_app.exe", "replacement build")
        assert_eq(
          @fs.read_file(source + "/window_app.exe").text(),
          "replacement build",
        )
        assert_eq(child.try_wait(), None)
        child.cancel()
      })
    })
  })
}
