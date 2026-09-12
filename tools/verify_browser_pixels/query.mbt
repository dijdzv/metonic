///|
async fn verify_query_pointer(host : BrowserHost) -> Unit {
  let original = command(host, { "op": "value", "selector": "#text-input" })
  for width in [1000, 600] {
    ignore(command(host, { "op": "viewport", "width": width }))
    guard command(host, { "op": "view-bounds" }) is Json::Array(bounds) &&
      bounds.length() == 5 else {
      fail("query bounds missing")
    }
    let query_width = int_field(bounds[4], "width")
    let scroll = 50 * 24 - (query_width - 16)
    let clicked = (scroll + 64 - 8 + 12) / 24
    let caret_x = 8 + clicked * 24 - scroll
    let kana = "あいうえおあいうえおあいうえおあいうえおあいうえおあいうえおあいうえおあいうえおあいうえおあいうえお"
    ignore(
      command(host, { "op": "fill", "selector": "#rpc-user", "value": kana }),
    )
    ignore(
      command(host, { "op": "press", "selector": "#rpc-user", "key": "End" }),
    )
    ignore(
      command(host, { "op": "click", "selector": "#rpc-user", "x": 64, "y": 16 }),
    )
    let pixels = navigation_pixels(
      host,
      true,
      "query-scrolled-hit-" + width.to_string(),
    )
    for y in 3..<21 {
      for channel in 0..<3 {
        require(
          pixels[(y * 200 + caret_x) * 4 + channel] == b'\x00',
          "scrolled query caret does not match the clicked character boundary",
        )
      }
    }
    ignore(
      command(host, { "op": "press", "selector": "#rpc-user", "key": "Delete" }),
    )
    require(
      command(host, { "op": "value", "selector": "#rpc-user" }) ==
      Json::string(kana[:clicked].to_owned() + kana[clicked + 1:].to_owned()),
      "scrolled query click edited a different character from the visible caret",
    )
    let long = "abc WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW"
    ignore(
      command(host, { "op": "fill", "selector": "#rpc-user", "value": long }),
    )
    ignore(
      command(host, { "op": "press", "selector": "#rpc-user", "key": "End" }),
    )
    ignore(
      command(host, {
        "op": "press",
        "selector": "#rpc-user",
        "key": "Shift+ArrowLeft",
      }),
    )
    ignore(
      command(host, { "op": "press", "selector": "#rpc-user", "key": "x" }),
    )
    require(
      command(host, { "op": "value", "selector": "#rpc-user" }) ==
      Json::string(long[:long.length() - 1].to_owned() + "x"),
      "scrolled query selection did not replace the final character",
    )
    ignore(
      command(host, { "op": "press", "selector": "#rpc-user", "key": "Home" }),
    )
    ignore(
      command(host, { "op": "click", "selector": "#rpc-user", "x": 10, "y": 16 }),
    )
    ignore(
      command(host, { "op": "press", "selector": "#rpc-user", "key": "Delete" }),
    )
    require(
      command(host, { "op": "value", "selector": "#rpc-user" }) ==
      Json::string(long[1:long.length() - 1].to_owned() + "x"),
      "query pointer did not return to the first glyph after scrolling",
    )
    ignore(command(host, { "op": "click", "selector": "#rpc-load" }))
    ignore(
      command(host, {
        "op": "wait-text",
        "selector": "#rpc-result",
        "text": "RPC: domain:not_found",
      }),
    )
    guard command(host, { "op": "rpc-body" }) is Json::String(body) &&
      @json.parse(body) is Json::Object(request) &&
      request.get("input") is Some(input) else {
      fail("long query request body missing")
    }
    require(
      string_field(input, "id") == long[1:long.length() - 1].to_owned() + "x",
      "query lookup truncated the scrolled value",
    )
    ignore(
      command(host, { "op": "fill", "selector": "#rpc-user", "value": "1" }),
    )
    ignore(
      command(host, { "op": "click", "selector": "#rpc-user", "x": 10, "y": 16 }),
    )
    ignore(
      command(host, { "op": "press", "selector": "#rpc-user", "key": "Delete" }),
    )
    require(
      command(host, { "op": "value", "selector": "#rpc-user" }) ==
      Json::string(""),
      "click at visible first glyph did not place caret before it",
    )
    ignore(
      command(host, { "op": "press", "selector": "#rpc-user", "key": "1" }),
    )
    ignore(command(host, { "op": "click", "selector": "#rpc-load" }))
    ignore(
      command(host, {
        "op": "wait-text",
        "selector": "#rpc-result",
        "text": "月兎",
      }),
    )
    ignore(
      command(host, {
        "op": "fill",
        "selector": "#rpc-user",
        "value": "missing",
      }),
    )
    ignore(command(host, { "op": "click", "selector": "#rpc-load" }))
    ignore(
      command(host, {
        "op": "wait-text",
        "selector": "#rpc-result",
        "text": "RPC: domain:not_found",
      }),
    )
    ignore(
      command(host, { "op": "fill", "selector": "#rpc-user", "value": "1" }),
    )
    ignore(command(host, { "op": "click", "selector": "#rpc-load" }))
    ignore(
      command(host, {
        "op": "wait-text",
        "selector": "#rpc-result",
        "text": "月兎",
      }),
    )
    require(
      command(host, { "op": "value", "selector": "#text-input" }) == original,
      "pointer query editing changed main editor",
    )
  }
  ignore(command(host, { "op": "viewport", "width": 1000 }))
  ignore(command(host, { "op": "click", "selector": "#reset" }))
}

///|
async fn verify_query_composition(host : BrowserHost) -> Unit {
  ignore(command(host, { "op": "focus", "selector": "#rpc-user" }))
  let count = command(host, { "op": "rpc-count" })
  ignore(
    command(host, {
      "op": "input-event",
      "selector": "#rpc-user",
      "type": "compositionstart",
      "start": 0,
      "end": 1,
    }),
  )
  ignore(
    command(host, {
      "op": "input-event",
      "selector": "#rpc-user",
      "type": "compositionupdate",
      "data": "日本",
    }),
  )
  ignore(
    command(host, {
      "op": "input-event",
      "selector": "#rpc-user",
      "type": "input",
      "data": "日本",
      "value": "日本",
      "composing": true,
    }),
  )
  ignore(command(host, { "op": "click", "selector": "#rpc-load" }))
  ignore(command(host, { "op": "sleep", "milliseconds": 100 }))
  require(
    command(host, { "op": "rpc-count" }) == count,
    "query preedit submitted a request",
  )
  ignore(
    command(host, {
      "op": "input-event",
      "selector": "#rpc-user",
      "type": "compositionend",
      "data": "",
      "value": "1",
      "start": 1,
      "end": 1,
    }),
  )
  require(
    command(host, { "op": "value", "selector": "#rpc-user" }) ==
    Json::string("1"),
    "query cancellation lost original ID",
  )
  ignore(command(host, { "op": "click", "selector": "#rpc-load" }))
  ignore(
    command(host, {
      "op": "wait-text",
      "selector": "#rpc-result",
      "text": "月兎",
    }),
  )
  ignore(command(host, { "op": "click", "selector": "#reset" }))
}
