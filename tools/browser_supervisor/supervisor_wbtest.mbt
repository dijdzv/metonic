///|
async test "invalid mode is rejected before spawning" {
  let mut rejected = false
  run_session(
    "invalid",
    "missing-server",
    [],
    "missing-verifier",
    [],
    100,
    server_capture=@ref.new([]),
    server_err_capture=@ref.new([]),
    verifier_capture=@ref.new([]),
    verifier_err_capture=@ref.new([]),
  ) catch {
    SupervisorFailure::Failure(message) => rejected = message == "invalid mode"
    error => raise error
  }
  assert_true(rejected)
}

///|
fn fixture_command() -> String {
  ".tools/moonbit/bin/moonrun.exe"
}

///|
fn fixture_wasm() -> String {
  "_build/wasm/release/build/tools/browser_supervisor_fixture/browser_supervisor_fixture.wasm"
}

///|
fn fixture_args(mode : String) -> Array[String] {
  [fixture_wasm(), mode]
}

///|
fn text(capture : @ref.Ref[Array[Byte]]) -> String raise Error {
  @utf8.decode(Bytes::from_array(capture.val))
}

///|
fn bytes_contains(data : Bytes, needle : Bytes) -> Bool {
  if needle.length() == 0 {
    return true
  }
  if needle.length() > data.length() {
    return false
  }
  for start in 0..<(data.length() - needle.length() + 1) {
    let mut matches = true
    for offset in 0..<needle.length() {
      if data[start + offset] != needle[offset] {
        matches = false
        break
      }
    }
    if matches {
      return true
    }
  }
  false
}

///|
async fn cleanup_fixture_child(pid : Int) -> Unit {
  ignore(
    @process.collect_output(
      "taskkill.exe",
      ["/PID", pid.to_string(), "/T", "/F"],
      no_console_window=true,
    ),
  )
}

///|
async test "fixture session captures ready server and verifier diagnostics" {
  let server = @ref.new([])
  let server_err = @ref.new([])
  let verifier = @ref.new([])
  let verifier_err = @ref.new([])
  run_session(
    "async",
    fixture_command(),
    fixture_args("server-ready"),
    fixture_command(),
    fixture_args("verifier-ok"),
    3000,
    readiness_ms=1000,
    server_capture=server,
    server_err_capture=server_err,
    verifier_capture=verifier,
    verifier_err_capture=verifier_err,
  )
  assert_true(text(server) == "http://127.0.0.1:4173/\n")
  assert_true(text(verifier).contains("FIXTURE_OK"))
  assert_true(text(verifier_err).contains("FIXTURE_DIAGNOSTIC"))
}

///|
async test "bad readiness rejects without starting verifier" {
  let server = @ref.new([])
  let server_err = @ref.new([])
  let verifier = @ref.new([])
  let verifier_err = @ref.new([])
  let mut failure : String? = None
  run_session(
    "async",
    fixture_command(),
    fixture_args("server-bad"),
    fixture_command(),
    fixture_args("verifier-ok"),
    1000,
    readiness_ms=200,
    server_capture=server,
    server_err_capture=server_err,
    verifier_capture=verifier,
    verifier_err_capture=verifier_err,
  ) catch {
    SupervisorFailure::Failure(message) => failure = Some(message)
    @async.TimeoutError => failure = Some("timeout")
    error => raise error
  }
  match failure {
    Some(message) => assert_true(message == "invalid browser server readiness")
    None => assert_true(false)
  }
  assert_true(verifier.val.length() == 0)
  assert_true(verifier_err.val.length() == 0)
}

///|
async test "silent readiness times out" {
  let server = @ref.new([])
  let server_err = @ref.new([])
  let verifier = @ref.new([])
  let verifier_err = @ref.new([])
  let mut failure : String? = None
  run_session(
    "async",
    fixture_command(),
    fixture_args("server-silent"),
    fixture_command(),
    fixture_args("verifier-ok"),
    1000,
    readiness_ms=100,
    server_capture=server,
    server_err_capture=server_err,
    verifier_capture=verifier,
    verifier_err_capture=verifier_err,
  ) catch {
    SupervisorFailure::Failure(message) => failure = Some(message)
    @async.TimeoutError => failure = Some("timeout")
    error => raise error
  }
  match failure {
    Some(message) => assert_true(message.contains("timeout"))
    None => assert_true(false)
  }
  assert_true(verifier.val.length() == 0)
}

///|
async test "early server exit reports status seven" {
  let server = @ref.new([])
  let server_err = @ref.new([])
  let verifier = @ref.new([])
  let verifier_err = @ref.new([])
  let mut failure : String? = None
  run_session(
    "async",
    fixture_command(),
    fixture_args("server-exit"),
    fixture_command(),
    fixture_args("verifier-hang"),
    2000,
    readiness_ms=500,
    server_capture=server,
    server_err_capture=server_err,
    verifier_capture=verifier,
    verifier_err_capture=verifier_err,
  ) catch {
    SupervisorFailure::Failure(message) => failure = Some(message)
    @async.TimeoutError => failure = Some("timeout")
    error => raise error
  }
  match failure {
    Some(message) =>
      assert_true(message.contains("browser server exited early: 7"))
    None => assert_true(false)
  }
}

///|
async test "verifier failure reports status seven" {
  let server = @ref.new([])
  let server_err = @ref.new([])
  let verifier = @ref.new([])
  let verifier_err = @ref.new([])
  let mut failure : String? = None
  run_session(
    "async",
    fixture_command(),
    fixture_args("server-ready"),
    fixture_command(),
    fixture_args("verifier-fail"),
    2000,
    readiness_ms=500,
    server_capture=server,
    server_err_capture=server_err,
    verifier_capture=verifier,
    verifier_err_capture=verifier_err,
  ) catch {
    SupervisorFailure::Failure(message) => failure = Some(message)
    @async.TimeoutError => failure = Some("timeout")
    error => raise error
  }
  match failure {
    Some(message) =>
      assert_true(message.contains("verifier exited with code 7"))
    None => assert_true(false)
  }
}

///|
async test "verifier overflow keeps a 65536 byte prefix" {
  let server = @ref.new([])
  let server_err = @ref.new([])
  let verifier = @ref.new([])
  let verifier_err = @ref.new([])
  let mut failure : String? = None
  run_session(
    "async",
    fixture_command(),
    fixture_args("server-ready"),
    fixture_command(),
    fixture_args("verifier-overflow"),
    3000,
    readiness_ms=500,
    server_capture=server,
    server_err_capture=server_err,
    verifier_capture=verifier,
    verifier_err_capture=verifier_err,
  ) catch {
    SupervisorFailure::Failure(message) => failure = Some(message)
    @async.TimeoutError => failure = Some("timeout")
    error => raise error
  }
  match failure {
    Some(message) =>
      assert_true(message.contains("verifier stdout output overflow"))
    None => assert_true(false)
  }
  assert_true(verifier.val.length() <= 65536)
  assert_true(verifier.val.length() == 65536)
  for byte in verifier.val {
    assert_true(byte == b'x')
  }
}

///|
async test "verifier tree child is alive then cleaned up" {
  let server = @ref.new([])
  let server_err = @ref.new([])
  let verifier = @ref.new([])
  let verifier_err = @ref.new([])
  let mut failure : String? = None
  run_session(
    "async",
    fixture_command(),
    fixture_args("server-ready"),
    fixture_command(),
    fixture_args("verifier-tree"),
    3000,
    readiness_ms=1000,
    server_capture=server,
    server_err_capture=server_err,
    verifier_capture=verifier,
    verifier_err_capture=verifier_err,
  ) catch {
    SupervisorFailure::Failure(message) => failure = Some(message)
    @async.TimeoutError => failure = Some("timeout")
    error => raise error
  }
  let output = text(verifier)
  assert_true(output.contains("CHILD_ALIVE=1"))
  let lines = output.split("\n").to_array()
  let pid_line = lines[0]
  let pid_parts = pid_line.split("=").to_array()
  let pid_text = pid_parts[1]
  let pid_json = @json.parse(pid_text)
  let pid = match pid_json {
    Json::Number(value, ..) => value.to_int()
    _ => {
      assert_true(false)
      0
    }
  }
  errdefer cleanup_fixture_child(pid)
  match failure {
    Some(message) => assert_true(message.contains("timeout"))
    None => assert_true(false)
  }
  let (status, listing, listing_err) = @process.collect_output(
    "tasklist.exe",
    ["/FI", "PID eq " + pid.to_string(), "/FO", "CSV", "/NH"],
    no_console_window=true,
  )
  assert_true(status == 0)
  assert_true(listing_err.binary().length() == 0)
  assert_true(
    !bytes_contains(
      listing.binary(),
      @utf8.encode("\"" + pid.to_string() + "\""),
    ),
  )
}
