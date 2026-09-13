///|
async fn capture_failure_dump(pid : Int) -> Unit raise Error {
  let path = ".work/release-exit-" +
    pid.to_string() +
    "-" +
    @async.now().to_string() +
    ".dmp"
  @async.with_timeout(10000, () => {
    let log = @process.redirect_to_file(path + ".log")
    defer log.close()
    let code = @process.run(
      ".work/procdump64.exe",
      ["-accepteula", "-mm", "-at", "8", pid.to_string(), path],
      no_console_window=true,
      stdout=log,
      stderr=log,
      cancel_handler=@process.hard_cancel(),
    )
    // ProcDump 12.01 uses 1 for a completed single dump.
    assert_eq(code, 1, msg="release dump failed; inspect " + path + ".log")
    assert_true(@fs.file_size(path) > 0L)
  })
  println("WINDOW_RELEASE_DUMP_SAVED " + path)
}
