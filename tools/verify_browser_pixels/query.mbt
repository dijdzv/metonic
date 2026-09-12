///|
async fn verify_query_pointer(host : BrowserHost) -> Unit {
  let original = command(host, { "op": "value", "selector": "#text-input" })
  for width in [1000, 600] {
    ignore(command(host, { "op": "viewport", "width": width }))
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
