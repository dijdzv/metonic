///|
test "only the failed check is shown, without successful checks or wrapper stacks" {
  let log = "pre-commit: first\nPASSED OLD\npre-commit timing: {}\npre-commit: compiler build\nsource.mbt:12: error: invalid type\npre-commit timing: {}\ncommand failed (7): compiler\nRuntimeError: wrapper stack\n"
  assert_eq(
    failure_output(log, truncated=false),
    "Failed check: compiler build\nsource.mbt:12: error: invalid type",
  )
}

///|
test "infrastructure failure without a check marker is retained" {
  assert_true(
    failure_output("input discovery failed", truncated=false).contains(
      "input discovery failed",
    ),
  )
  let result = failure_output(
    "VERIFICATION_INPUT_CONFIG_WRITTEN\nFailure(discovery failed)\n",
    truncated=false,
  )
  assert_false(result.contains("VERIFICATION_INPUT_CONFIG_WRITTEN"))
  assert_true(result.contains("discovery failed"))
}

///|
test "large diagnostics are bounded and explicit about truncation" {
  let lines = Array::make(100, "diagnostic context")
  let value = failure_output(lines.join("\n"), truncated=false)
  assert_true(value.contains("Diagnostic truncated"))
  assert_true(value.split("\n").to_array().length() <= 82)
  assert_true(
    failure_output("short tail", truncated=true).contains(
      "Diagnostic truncated",
    ),
  )
}

///|
test "empty failed command still produces an explanation" {
  assert_true(
    failure_output(
      "pre-commit: build\npre-commit timing: {}\ncommand failed (1): build",
      truncated=false,
    ).contains("without diagnostic output"),
  )
}

///|
async test "logged commands preserve failure status and save output without replaying it" {
  let directory = @fs.tmpdir(prefix="metonic-hook-output-test")
  let path = directory + "/output.log"
  defer @async.protect_from_cancel(() => @fs.rmdir(directory, recursive=true))
  let fixture = "_build/wasm/release/build/tools/browser_supervisor_fixture/browser_supervisor_fixture.wasm"
  let status = run_logged(
    ".tools/moonbit/bin/moonrun.exe",
    [fixture, "verifier-transport"],
    path,
  )
  assert_eq(status, 7)
  let (tail, truncated) = log_tail(path)
  assert_false(truncated)
  assert_true(tail.contains("ERR_NO_BUFFER_SPACE"))
  assert_eq(
    run_logged(".tools/moonbit/bin/moonrun.exe", [fixture, "verifier-ok"], path),
    0,
  )
  let (tail, _) = log_tail(path)
  assert_true(tail.contains("FIXTURE_OK"))
  assert_false(tail.contains("ERR_NO_BUFFER_SPACE"))
}

///|
async test "missing executable is not mistaken for success" {
  let directory = @fs.tmpdir(prefix="metonic-hook-output-spawn")
  defer @async.protect_from_cancel(() => @fs.rmdir(directory, recursive=true))
  let mut failed = false
  try {
    let status = run_logged(
      "metonic-does-not-exist.exe",
      [],
      directory + "/output.log",
    )
    failed = status != 0
  } catch {
    _ => failed = true
  }
  assert_true(failed)
}

///|
async test "log tail memory is bounded for large files" {
  let directory = @fs.tmpdir(prefix="metonic-hook-output-tail")
  defer @async.protect_from_cancel(() => @fs.rmdir(directory, recursive=true))
  let path = directory + "/output.log"
  @fs.write_file(path, Bytes::make(100000, b'x'))
  let (tail, truncated) = log_tail(path)
  assert_true(truncated)
  assert_eq(tail.length(), 65536)
}
