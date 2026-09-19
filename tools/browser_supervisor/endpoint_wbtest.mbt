///|
test "readiness accepts assigned loopback ports and rejects incomplete or foreign endpoints" {
  assert_eq(
    ready_endpoint("http://127.0.0.1:49152/\n"),
    "http://127.0.0.1:49152",
  )
  assert_eq(
    ready_endpoint("http://127.0.0.1:65535/\n"),
    "http://127.0.0.1:65535",
  )
  for
    line in [
      "http://127.0.0.1:0/\n", "http://127.0.0.1:65536/\n", "http://127.0.0.1:49152/",
      "http://127.0.0.1:49152/path\n", "http://example.com:49152/\n", "http://127.0.0.1:/\n",
      "http://127.0.0.1:+123/\n", "http://127.0.0.1:123/a/\n",
    ] {
    let mut rejected = false
    ignore(ready_endpoint(line)) catch {
      SupervisorFailure::Failure(_) => rejected = true
      error => raise error
    }
    assert_true(rejected, msg=line)
  }
}

///|
test "transport observation attributes only the assigned server port" {
  let sample = b"TCP 127.0.0.1:4173 127.0.0.1:50000 ESTABLISHED\nTCP 127.0.0.1:49152 127.0.0.1:50001 CLOSE_WAIT\n"
  assert_eq(
    tcp_counts(sample, endpoint="127.0.0.1:49152"),
    (
      {
        "tcp_states": { "ESTABLISHED": 1, "CLOSE_WAIT": 1 },
        "browser_server_states": { "CLOSE_WAIT": 1 },
      } : Json),
  )
}
