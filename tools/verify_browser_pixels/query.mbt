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
