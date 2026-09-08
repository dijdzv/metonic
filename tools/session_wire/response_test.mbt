///|
test "ready identity is required only for the initial headless handshake" {
  let ready =
    #|{"id":0,"ok":true,"session_id":"session"}
  assert_eq(validate_response(ready, false, true), "")
  assert_eq(validate_response(ready, false, false), "invalid response schema")
  assert_eq(
    validate_response(
      (
        #|{"id":0,"ok":true,"session_id":""}
      ),
      false,
      true,
    ),
    "invalid session ready response",
  )
}

///|
test "headless snapshots and error envelopes remain distinct" {
  let response =
    #|{"id":1,"ok":true,"response":{"id":1,"version":1,"ok":true,"state":[0,0,120,72,0,0,640,360],"frame":1}}
  assert_eq(validate_response(response, false, false), "")
  assert_eq(validate_response(response, true, false), "invalid window response")
  assert_eq(
    validate_response(
      (
        #|{"id":1,"ok":false,"error":"stale"}
      ),
      false,
      false,
    ),
    "",
  )
  assert_eq(
    validate_response(
      (
        #|{"id":1,"ok":false}
      ),
      false,
      false,
    ),
    "invalid response error",
  )
  assert_eq(
    validate_response(
      (
        #|{"id":1,"ok":true,"response":{}}
      ),
      false,
      false,
    ),
    "invalid native response",
  )
}

///|
test "window state requires integral counters and a bounded task status" {
  for
    entry in [
      (1.0, 0, ""),
      (0.5, 0, "invalid native response"),
      (-1.0, 0, "invalid native response"),
      (1.0, 6, "invalid native response"),
    ] {
    let (frames, status, expected) = entry
    let response : Json = {
      "id": 1,
      "error": "",
      "text": "日本😀",
      "semantic_revision": 1,
      "frames": frames,
      "task_status": status,
    }
    assert_eq(validate_response(response.stringify(), true, false), expected)
  }
  assert_eq(
    validate_response(
      (
        #|{"id":1,"error":"composition_active"}
      ),
      true,
      false,
    ),
    "",
  )
}

///|
test "malformed JSON and invalid identities fail before dispatch" {
  assert_eq(
    validate_response("{", false, false),
    "invalid native session response",
  )
  for id in [0.0, -1.0, 1.5, 9007199254740992.0] {
    let response : Json = { "id": id, "ok": false, "error": "failed" }
    assert_eq(
      validate_response(response.stringify(), false, false),
      "invalid response schema",
    )
  }
}
