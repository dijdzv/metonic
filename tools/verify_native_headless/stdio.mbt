///|
async fn verify_stdio(
  root : String,
  bridge : String,
  capture_path : String,
) -> Unit raise Error {
  let executable = root +
    "/_build/native/release/build/examples/p0/native_headless/native_headless.exe"
  let stderr = with_raw(executable, bridge, capture_path, async fn(session) {
    let first = session.request(request(1, 101, "snapshot", ""))
    assert_meta(first, 101, "stdio snapshot")
    is_true(first, "stdio snapshot")
    session.writer.write(
      request(1, 102, "snapshot", "") +
      "\r\n" +
      request(1, 103, "snapshot", "") +
      "\n",
    )
    let second = session.read_response_line()
    assert_meta(second, 102, "stdio CRLF")
    is_true(second, "stdio CRLF")
    let third = session.read_response_line()
    assert_meta(third, 103, "stdio batch")
    is_true(third, "stdio batch")
    let bad_version = session.request(request(2, 104, "shutdown", ""))
    assert_meta(bad_version, 104, "stdio version")
    require(
      field(bad_version, "error") == Some(Json::string("unsupported_version")),
      "stdio version error",
    )
    let stale_shutdown = session.request(
      request(1, 105, "shutdown", ",\"expected_revision\":99"),
    )
    assert_meta(stale_shutdown, 105, "stdio stale shutdown")
    require(
      field(stale_shutdown, "error") == Some(Json::string("stale_revision")),
      "stdio stale shutdown error",
    )
    let still_alive = session.request(request(1, 106, "snapshot", ""))
    assert_meta(still_alive, 106, "stdio after rejected shutdown")
    is_true(still_alive, "stdio after rejected shutdown")
    let padded_base = request(1, 108, "snapshot", "")
    let padding = 4095 - @utf8.encode(padded_base).length()
    let padded = padded_base + String::from_array(Array::make(padding, ' '))
    require(@utf8.encode(padded).length() == 4095, "stdio 4095-byte LF request")
    session.writer.write(padded + "\n")
    let padded_lf = session.read_response_line()
    assert_meta(padded_lf, 108, "stdio 4095-byte LF")
    is_true(padded_lf, "stdio 4095-byte LF")

    let padded_crlf_base = request(1, 109, "snapshot", "")
    let crlf_padding = 4095 - @utf8.encode(padded_crlf_base).length()
    let padded_crlf = padded_crlf_base +
      String::from_array(Array::make(crlf_padding, ' '))
    require(
      @utf8.encode(padded_crlf).length() == 4095,
      "stdio 4095-byte CRLF request",
    )
    session.writer.write(padded_crlf + "\r")
    session.writer.write("\n")
    let padded_crlf_response = session.read_response_line()
    assert_meta(padded_crlf_response, 109, "stdio 4095-byte CRLF")
    is_true(padded_crlf_response, "stdio 4095-byte CRLF")

    let too_long = String::from_array(Array::make(4096, 'x'))
    let too_long_response = session.request(too_long)
    require(
      field(too_long_response, "error") == Some(Json::string("line_too_long")),
      "stdio 4096-byte rejection",
    )
    let recovered = session.request(request(1, 110, "snapshot", ""))
    assert_meta(recovered, 110, "stdio after 4096-byte rejection")
    is_true(recovered, "stdio after 4096-byte rejection")

    let invalid = Bytes::from_array([b'\xff', b'\n'])
    require(
      session.writer.write_once(invalid, offset=0, len=2) == 2,
      "stdio invalid UTF-8 write",
    )
    let invalid_response = session.read_response_line()
    require(
      field(invalid_response, "error") == Some(Json::string("invalid_utf8")),
      "stdio invalid UTF-8",
    )
    let invalid_recovered = session.request(request(1, 111, "snapshot", ""))
    assert_meta(invalid_recovered, 111, "stdio after invalid UTF-8")
    is_true(invalid_recovered, "stdio after invalid UTF-8")

    session.writer.write(
      "{\"version\":1,\r\"id\":112,\r\"op\":\"snapshot\"\r}\r\n",
    )
    let bare_cr_response = session.read_response_line()
    assert_meta(bare_cr_response, 112, "stdio JSON CR whitespace")
    is_true(bare_cr_response, "stdio JSON CR whitespace")
    let shutdown = session.request(request(1, 107, "shutdown", ""))
    assert_meta(shutdown, 107, "stdio shutdown")
    is_true(shutdown, "stdio shutdown")
    session.finish()
  })
  let eof_stderr = with_raw(executable, bridge, capture_path, async fn(
    session,
  ) {
    session.writer.write(request(1, 106, "snapshot", ""))
    session.writer.close()
    let eof_response = session.read_response_line()
    assert_meta(eof_response, 106, "stdio EOF")
    is_true(eof_response, "stdio EOF")
    session.finish()
  })
  let _ = eof_stderr
  let _ = with_raw(executable, bridge, capture_path + ".stdio", async fn(
    session,
  ) {
    let captured = session.request(request(1, 120, "capture", ""))
    assert_meta(captured, 120, "stdio close stdout capture")
    is_true(captured, "stdio close stdout capture")
    session.reader.close()
    session.writer.write(request(1, 123, "snapshot", "") + "\n")
    let exit_code = @async.with_timeout(10000, () => session.process.wait())
    require(exit_code == 0, "stdio close stdout bounded exit")
    session.writer.close()
    session.finished = true
  })
  let _ = with_raw(executable, bridge, capture_path, async fn(session) {
    session.writer.write(
      request(1, 121, "shutdown", "") +
      "\n" +
      request(1, 122, "snapshot", "") +
      "\n",
    )
    let shutdown = session.read_response_line()
    assert_meta(shutdown, 121, "stdio shutdown batch")
    is_true(shutdown, "stdio shutdown batch")
    session.finish()
  })
  @fs.write_file(capture_path + ".stdio.stderr.log", @utf8.encode(stderr))
}
