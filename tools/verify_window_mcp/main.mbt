///|
#external
pub type Client

///|
#export_name("verify_sdk_cancel")
pub fn verify_sdk_cancel(
  client : Client,
  rejected : Bool,
  notified : Bool,
) -> @js_async.Promise[String] {
  @js_async.Promise::from_async(async fn() {
    assert_true(rejected)
    assert_true(notified)
    for _ in 0..<40 {
      let request : Json = { "name": "window_snapshot", "arguments": {} }
      let reply : Reply = @json.from_json(
        @json.parse(call(client, request.stringify()).wait()),
      )
      if reply.isError == Some(true) {
        assert_true(
          reply.content[0].text.contains("closed") ||
          reply.content[0].text.contains("aborted"),
        )
        return "WINDOW_MCP_SDK_CANCEL_OK"
      }
      sleep(25).wait()
    }
    fail("SDK cancellation did not close the attached control session")
  })
}

///|
struct CancellationResult {
  statuses : Array[String]
  session : String
  pending : Int
  forced_kill : Bool
  exit_code : Int
} derive(FromJson)

///|
#export_name("verify_cancel_result")
pub fn verify_cancel_result(
  raw : String,
  expected_session : String,
) -> Unit raise {
  let result : CancellationResult = @json.from_json(@json.parse(raw))
  assert_eq(result.statuses, ["rejected", "rejected"])
  assert_eq(result.session, expected_session)
  assert_eq(result.pending, 0)
  assert_false(result.forced_kill)
  assert_eq(result.exit_code, 0)
}

///|
#export_name("verify_attachment")
pub fn verify_attachment(
  client : Client,
  session : String,
) -> @js_async.Promise[String] {
  @js_async.Promise::from_async(async fn() {
    let before = invoke(client, { "name": "window_snapshot", "arguments": {} })
    assert_eq(before.session_id, session)
    let inserted = invoke(client, {
      "name": "window_insert",
      "arguments": {
        "text": "日本",
        "expected_semantic_revision": before.semantic_revision,
      },
    })
    assert_eq(inserted.text, before.text + "日本")
    assert_eq(inserted.session_id, session)
    let deleted = invoke(client, { "name": "window_backspace", "arguments": {} })
    assert_eq(deleted.text, before.text + "日")
    let restored = invoke(client, {
      "name": "window_backspace",
      "arguments": {},
    })
    assert_eq(restored.text, before.text)
    assert_eq(restored.session_id, session)
    "WINDOW_MCP_ATTACH_OK"
  })
}

///|
extern "js" fn call(
  client : Client,
  request : String,
) -> @js_async.Promise[String] =
  #| async (client, request) => JSON.stringify(await client.callTool(JSON.parse(request)))

///|
struct Content {
  text : String
} derive(FromJson)

///|
struct Reply {
  content : Array[Content]
  isError : Bool?
} derive(FromJson)

///|
struct State {
  ime_events : Array[Json]
  raw_ime_events : Array[Json]
  raw_ime_dropped : Int64
  ime_dropped : Int64
  host_input_events : HostInputEvents
  view : Array[ViewNode]
  text : String
  semantic_revision : Int
  session_id : String
  task_status : Int
  rpc_result : String
} derive(FromJson)

///|
struct HostInputEvents {
  key_presses : Int
  pointer_presses : Int
  last_key : String
} derive(FromJson, Eq, Debug)

///|
struct ViewNode {
  id : Json
  role : String
  text : String
  action : Json
  x : Int
  y : Int
  width : Int
  height : Int
} derive(FromJson)

///|
extern "js" fn sleep(milliseconds : Int) -> @js_async.Promise[Unit] =
  #| (milliseconds) => new Promise(resolve => setTimeout(resolve, milliseconds))

///|
async fn verify_rpc(
  client : Client,
  user_id : String,
  expected : String,
  status : Int,
  text : String,
  label? : String = expected.trim().to_owned(),
) -> Unit {
  ignore(
    invoke(client, {
      "name": "window_load_user",
      "arguments": { "user_id": user_id },
    }),
  )
  for _ in 0..<150 {
    sleep(20).wait()
    let state = invoke(client, { "name": "window_snapshot", "arguments": {} })
    if state.task_status != 1 {
      assert_eq(state.task_status, status)
      assert_eq(state.rpc_result, expected)
      assert_eq(state.text, text)
      assert_eq(state.view[0].text, text)
      assert_eq(state.view[2].text, label)
      return
    }
  }
  fail("RPC did not finish")
}

///|
async fn invoke(client : Client, request : Json) -> State {
  let reply : Reply = @json.from_json(
    @json.parse(call(client, request.stringify()).wait()),
  )
  assert_true(reply.isError != Some(true))
  @json.from_json(@json.parse(reply.content[0].text))
}

///|
#export_name("verify")
pub fn verify(client : Client) -> @js_async.Promise[String] {
  @js_async.Promise::from_async(async fn() {
    let before = invoke(client, { "name": "window_snapshot", "arguments": {} })
    assert_true(before.ime_events.length() <= 128)
    assert_true(before.raw_ime_events.length() <= 128)
    assert_eq(before.ime_dropped, 0L)
    assert_eq(before.raw_ime_dropped, 0L)
    assert_eq(before.view.length(), 7)
    assert_eq(before.view[6].id, Json::number(6))
    assert_eq(before.view[6].role, "text_input")
    assert_eq(before.view[6].text, "1")
    assert_eq(before.view[0].id, Json::number(2))
    assert_eq(before.view[1].id, Json::number(3))
    assert_eq(before.view[2].id, Json::null())
    assert_eq(before.view[1].role, "button")
    assert_eq(before.view[1].text, "Load user")
    assert_eq(before.view[1].action, Json::string("load_user"))
    assert_eq(before.view[0].action, Json::null())
    assert_eq(
      (
        before.view[1].x,
        before.view[1].y,
        before.view[1].width,
        before.view[1].height,
      ),
      (8, 144, 176, 40),
    )
    let after = invoke(client, {
      "name": "window_insert",
      "arguments": {
        "text": "日本",
        "expected_semantic_revision": before.semantic_revision,
      },
    })
    assert_eq(after.text, before.text + "日本")
    assert_eq(after.semantic_revision, before.semantic_revision + 1)
    assert_eq(after.host_input_events, before.host_input_events)
    assert_eq(after.ime_events, before.ime_events)
    assert_eq(after.raw_ime_events, before.raw_ime_events)
    assert_eq(after.ime_dropped, before.ime_dropped)
    assert_eq(after.session_id, before.session_id)
    let deleted = invoke(client, {
      "name": "window_backspace",
      "arguments": { "expected_semantic_revision": after.semantic_revision },
    })
    assert_eq(deleted.text, before.text + "日")
    let stale_request : Json = {
      "name": "window_insert",
      "arguments": {
        "text": "wrong",
        "expected_semantic_revision": before.semantic_revision,
      },
    }
    let stale : Reply = @json.from_json(
      @json.parse(call(client, stale_request.stringify()).wait()),
    )
    assert_eq(stale.isError, Some(true))
    assert_eq(stale.content[0].text, "stale_revision")
    let unchanged = invoke(client, {
      "name": "window_snapshot",
      "arguments": {},
    })
    assert_eq(unchanged.text, deleted.text)
    assert_eq(unchanged.semantic_revision, deleted.semantic_revision)
    let pending = invoke(client, {
      "name": "window_start_update",
      "arguments": {},
    })
    assert_eq(pending.task_status, 1)
    let canceled = invoke(client, {
      "name": "window_cancel_update",
      "arguments": {},
    })
    assert_eq(canceled.task_status, 4)
    let capture_request : Json = { "name": "window_capture", "arguments": {} }
    let captured : ImageReply = @json.from_json(
      @json.parse(call(client, capture_request.stringify()).wait()),
    )
    assert_eq(captured.content[1].mimeType, Some("image/png"))
    let image = @image.decode_png(
      @base64.decode(captured.content[1].data.unwrap()),
    )
    assert_eq(image.width, 640)
    assert_eq(image.height, 360)
    let rectangle = (170 * image.width + 300) * 4
    assert_true(image.data[rectangle + 1] > image.data[rectangle])
    assert_true(image.data[rectangle + 2] > image.data[rectangle])
    assert_eq(image.data[rectangle + 3], 255)
    let mut dark = 0
    for y in 8..<104 {
      for x in 8..<632 {
        let offset = (y * image.width + x) * 4
        assert_eq(image.data[offset + 3], 255)
        if image.data[offset] < 128 &&
          image.data[offset + 1] < 128 &&
          image.data[offset + 2] < 128 {
          dark += 1
        }
      }
    }
    assert_true(dark > 100)
    verify_rpc(client, "1", "\n月兎", 2, deleted.text)
    verify_rpc(
      client,
      "missing",
      "\nRPC: domain:not_found",
      3,
      deleted.text,
      label="Not found",
    )
    let selected = invoke(client, {
      "name": "window_select",
      "arguments": {
        "selection_start": 0,
        "selection_end": deleted.text.length(),
      },
    })
    let emoji = invoke(client, {
      "name": "window_insert",
      "arguments": {
        "text": "A😀B",
        "expected_semantic_revision": selected.semantic_revision,
      },
    })
    assert_eq(emoji.text, "A😀B")
    let invalid_request : Json = {
      "name": "window_select",
      "arguments": { "selection_start": 2, "selection_end": 3 },
    }
    let invalid : Reply = @json.from_json(
      @json.parse(call(client, invalid_request.stringify()).wait()),
    )
    assert_eq(invalid.isError, Some(true))
    assert_eq(invalid.content[0].text, "invalid_selection")
    let range = invoke(client, {
      "name": "window_select",
      "arguments": {
        "selection_start": 1,
        "selection_end": 3,
        "expected_semantic_revision": emoji.semantic_revision,
      },
    })
    assert_true(selection_pixels(client) > 50)
    let replaced = invoke(client, {
      "name": "window_insert",
      "arguments": {
        "text": "日本",
        "expected_semantic_revision": range.semantic_revision,
      },
    })
    assert_eq(replaced.text, "A日本B")
    assert_eq(selection_pixels(client), 0)
    "WINDOW_MCP_OK"
  })
}

///|
struct ImageContent {
  data : String?
  mimeType : String?
} derive(FromJson)

///|
struct ImageReply {
  content : Array[ImageContent]
} derive(FromJson)

///|
async fn selection_pixels(client : Client) -> Int {
  let request : Json = { "name": "window_capture", "arguments": {} }
  let captured : ImageReply = @json.from_json(
    @json.parse(call(client, request.stringify()).wait()),
  )
  let image = @image.decode_png(
    @base64.decode(captured.content[1].data.unwrap()),
  )
  let mut selected = 0
  for y in 8..<104 {
    for x in 8..<632 {
      let offset = (y * image.width + x) * 4
      if image.data[offset] < image.data[offset + 1] &&
        image.data[offset + 1] < image.data[offset + 2] {
        selected += 1
      }
    }
  }
  selected
}
