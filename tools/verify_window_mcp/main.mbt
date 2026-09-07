///|
#external
pub type Client

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
  text : String
  semantic_revision : Int
  session_id : String
  task_status : Int
} derive(FromJson)

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
    let after = invoke(client, {
      "name": "window_insert",
      "arguments": {
        "text": "日本",
        "expected_semantic_revision": before.semantic_revision,
      },
    })
    assert_eq(after.text, before.text + "日本")
    assert_eq(after.semantic_revision, before.semantic_revision + 1)
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
    "WINDOW_MCP_OK"
  })
}
