///|
async fn query_sample(host : BrowserHost) -> Json {
  let sampled = command(host, { "op": "trace-sample" })
  guard field(sampled, "fields") is Some(Array(fields)) else {
    raise VerifyFailure::Failure("missing sampled fields")
  }
  require(fields.length() == 2, "both input samples required")
  require(
    string_field(fields[1], "field") == "rpc-user",
    "query sample attribution",
  )
  @json.parse(string_field(fields[1], "shared"))
}

///|
async fn verify_query_observation(host : BrowserHost) -> Unit {
  let original_text = command(host, { "op": "value", "selector": "#text-input" })
  let original_query = command(host, { "op": "value", "selector": "#rpc-user" })
  ignore(
    command(host, {
      "op": "fill",
      "selector": "#text-input",
      "value": "文😀字",
    }),
  )
  ignore(
    command(host, { "op": "fill", "selector": "#rpc-user", "value": "A😀B" }),
  )
  ignore(command(host, { "op": "trace-start" }))
  ignore(
    command(host, {
      "op": "input-event",
      "selector": "#rpc-user",
      "type": "select",
      "start": 1,
      "end": 3,
    }),
  )
  let selected = query_sample(host)
  require(
    string_field(selected, "text") == "A😀B" &&
    int_field(selected, "start") == 1 &&
    int_field(selected, "end") == 3,
    "query UTF-16 selection sample",
  )
  ignore(
    command(host, {
      "op": "input-event",
      "selector": "#rpc-user",
      "type": "compositionstart",
    }),
  )
  require(
    field(query_sample(host), "composing") == Some(Json::boolean(true)),
    "query composition start sample",
  )
  ignore(
    command(host, {
      "op": "input-event",
      "selector": "#rpc-user",
      "type": "compositionupdate",
      "data": "日",
    }),
  )
  ignore(
    command(host, {
      "op": "input-event",
      "selector": "#rpc-user",
      "type": "compositionend",
      "value": "AB",
      "start": 1,
      "end": 1,
    }),
  )
  let ended = query_sample(host)
  require(
    string_field(ended, "text") == "AB" &&
    int_field(ended, "start") == 1 &&
    int_field(ended, "end") == 1 &&
    field(ended, "composing") == Some(Json::boolean(false)),
    "query cancellation sample",
  )
  require(
    command(host, { "op": "value", "selector": "#text-input" }) ==
    Json::string("文😀字"),
    "query observation changed Text",
  )
  ignore(command(host, { "op": "trace-stop" }))
  ignore(
    command(host, {
      "op": "fill",
      "selector": "#text-input",
      "value": original_text,
    }),
  )
  ignore(
    command(host, {
      "op": "fill",
      "selector": "#rpc-user",
      "value": original_query,
    }),
  )
}

///|
#export_name("runQueryObservation")
pub fn run_query_observation_export(
  host : BrowserHost,
) -> @js_async.Promise[Unit] {
  @js_async.Promise::from_async(async fn() { verify_query_observation(host) })
}
