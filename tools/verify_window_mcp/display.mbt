///|
#export_name("verify_display")
pub fn verify_display(client : Client) -> @js_async.Promise[String] {
  @js_async.Promise::from_async(async fn() {
    ignore(invoke(client, { "name": "window_snapshot", "arguments": {} }))
    sleep(50).wait()
    ignore(
      invoke(client, {
        "name": "window_insert",
        "arguments": { "text": "display" },
      }),
    )
    sleep(50).wait()
    let target = invoke(client, {
      "name": "window_insert",
      "arguments": { "text": " confirmation" },
    })
    let wait_request : Json = {
      "name": "window_wait_display",
      "arguments": {
        "frame_id": target.retained_frame_id,
        "frame_scope": target.frame_scope,
        "timeout_ms": 2000,
      },
    }
    let wait_reply : Reply = @json.from_json(
      @json.parse(call(client, wait_request.stringify()).wait()),
    )
    if wait_reply.isError == Some(true) {
      let current = invoke(client, {
        "name": "window_snapshot",
        "arguments": {},
      })
      fail(
        "display wait failed: " +
        wait_reply.content[0].text +
        "; requested=" +
        target.retained_frame_id +
        "; current=" +
        current.retained_frame_id,
      )
    }
    let waited : State = @json.from_json(
      @json.parse(wait_reply.content[0].text),
    )
    assert_eq(waited.retained_frame_id, target.retained_frame_id)
    let request : Json = {
      "name": "window_capture_retained",
      "arguments": {
        "frame_id": target.retained_frame_id,
        "frame_scope": target.frame_scope,
      },
    }
    let reply = @json.parse(call(client, request.stringify()).wait())
    guard reply is { "content": Array(content), .. } else {
      fail("missing MCP content")
    }
    assert_eq(content.length(), 3)
    assert_true(content[1] is { "type": "image", "mimeType": "image/png", .. })
    guard content[2] is { "text": String(metadata), .. } else {
      fail("missing image metadata")
    }
    guard @json.parse(metadata)
      is { "frame_id": String(id), "display_completion_confirmed": true, .. } else {
      fail("image is not display confirmed")
    }
    assert_eq(id, target.retained_frame_id)
    "WINDOW_MCP_DISPLAY_OK"
  })
}
