///|
fn metadata(version : Int, session : String, pipe : String) -> String {
  let value : Json = {
    "protocol_version": version,
    "session_id": session,
    "pipe": pipe,
  }
  value.stringify()
}

///|
test "discovery rejects remote paths, unsupported versions and oversized metadata" {
  let valid : Json = {
    "protocol_version": 1,
    "session_id": "abc",
    "pipe": "\\\\.\\pipe\\test",
  }
  assert_eq(@window_attach.parse_discovery(valid.stringify()).session_id, "abc")
  for
    text in [
      metadata(1, "abc", "C:/file"),
      metadata(1, "abc", "\\\\remote\\pipe\\test"),
      metadata(2, "abc", "\\\\.\\pipe\\test"),
      metadata(1, "", "\\\\.\\pipe\\test"),
      String::make(4097, ' '),
    ] {
    let rejected = try {
      ignore(@window_attach.parse_discovery(text))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}
