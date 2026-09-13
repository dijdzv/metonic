///|
test "TCP observation emits counts without endpoints or unknown state text" {
  let sample = b"\xff\xfe header\r\n  TCP    127.0.0.1:4173   127.0.0.1:50000  ESTABLISHED\r\n TCP 127.0.0.1:50001 127.0.0.1:4173 TIME_WAIT\r\n TCP 192.0.2.1:10 198.51.100.1:20 CLOSE_WAIT\r\n TCP private:3 other:4 secret\r\n UDP 127.0.0.1:4173 *:* LISTENING\r\n"
  let actual = tcp_counts(sample)
  assert_eq(
    actual,
    (
      {
        "tcp_states": { "ESTABLISHED": 1, "TIME_WAIT": 1, "CLOSE_WAIT": 1 },
        "browser_server_states": { "ESTABLISHED": 1, "TIME_WAIT": 1 },
      } : Json),
  )
}

///|
async test "missing observation tool does not propagate an error or expose command details" {
  let value = @async.with_timeout(3000, () => {
    collect_tcp_observation(command="metonic-missing-observation-tool.exe")
  })
  assert_true(
    value is { "status": "unavailable", "phase": "after_verifier_report", .. },
  )
  assert_false(value.stringify().contains("metonic-missing"))
}

///|
async test "hung observation tool is bounded and reports unavailable" {
  let value = @async.with_timeout(3000, () => {
    collect_tcp_observation(
      command=fixture_command(),
      arguments=fixture_args("verifier-hang"),
    )
  })
  assert_true(value is { "status": "unavailable", .. })
}

///|
async test "excessive observation output is rejected rather than counted partially" {
  let value = @async.with_timeout(3000, () => {
    collect_tcp_observation(
      command=fixture_command(),
      arguments=fixture_args("verifier-overflow"),
    )
  })
  assert_true(value is { "status": "unavailable", .. })
  assert_false(value.stringify().contains("counts"))
}

///|
async test "transport failure samples resources without replacing verifier exit status" {
  let observation = @ref.new(Json::null())
  let mut failed = false
  run_session(
    "async",
    fixture_command(),
    fixture_args("server-ready"),
    fixture_command(),
    fixture_args("verifier-transport"),
    4000,
    server_capture=@ref.new([]),
    server_err_capture=@ref.new([]),
    verifier_capture=@ref.new([]),
    verifier_err_capture=@ref.new([]),
    transport_capture=observation,
  ) catch {
    SupervisorFailure::Failure(message) => {
      assert_true(message.contains("verifier exited with code 7"))
      failed = true
    }
    error => raise error
  }
  assert_true(failed)
  assert_true(
    observation.val is { "status": "available", "counts": Object(_), .. } ||
    observation.val is { "status": "unavailable", .. },
  )
}
