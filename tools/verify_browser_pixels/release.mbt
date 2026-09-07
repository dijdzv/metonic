///|
async fn release_crop(host : BrowserHost, name : String) -> Json {
  crop({ "png": command(host, { "op": "image", "name": name }), "width": 640 })
}

///|
async fn run_release(host : BrowserHost) -> String {
  ignore(command(host, { "op": "goto" }))
  ignore(
    command(host, { "op": "wait-text", "selector": "#status", "text": "Ready" }),
  )
  require(
    command(host, { "op": "no-probe" }) == Json::boolean(true),
    "release exposes development control",
  )
  let initial = release_crop(host, "initial")
  ignore(text_initial(initial))
  ignore(
    command(host, {
      "op": "fill",
      "selector": "#text-input",
      "value": "配布版 ABC 😀",
    }),
  )
  let edited = release_crop(host, "edited")
  ignore(text_initial(edited))
  ignore(
    text_compare({
      "actual": field(edited, "data").unwrap(),
      "expected": field(initial, "data").unwrap(),
      "equal": false,
    }),
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
    command(host, { "op": "value", "selector": "#text-input" }) ==
    Json::string("配布版 ABC 😀"),
    "release RPC changed editor",
  )
  let loaded = release_crop(host, "loaded")
  ignore(
    text_compare({
      "actual": field(loaded, "data").unwrap(),
      "expected": field(edited, "data").unwrap(),
      "equal": false,
    }),
  )
  ignore(
    command(host, { "op": "fill", "selector": "#rpc-user", "value": "missing" }),
  )
  ignore(command(host, { "op": "click", "selector": "#rpc-load" }))
  ignore(
    command(host, {
      "op": "wait-text",
      "selector": "#rpc-result",
      "text": "RPC: domain:not_found",
    }),
  )
  ignore(command(host, { "op": "click", "selector": "#task-start" }))
  ignore(command(host, { "op": "click", "selector": "#task-cancel" }))
  ignore(
    command(host, {
      "op": "wait-text",
      "selector": "#task-state",
      "text": "Canceled",
    }),
  )
  let before_width = command(host, { "op": "width" })
  ignore(command(host, { "op": "viewport", "width": 740 }))
  require(
    command(host, { "op": "width" }) != before_width,
    "release resize did not reach canvas",
  )
  require(
    command(host, { "op": "value", "selector": "#text-input" }) ==
    Json::string("配布版 ABC 😀"),
    "release resize changed editor",
  )
  ignore(command(host, { "op": "viewport", "width": 1000 }))
  ignore(command(host, { "op": "click", "selector": "#reset" }))
  ignore(
    command(host, { "op": "fill", "selector": "#text-input", "value": "" }),
  )
  ignore(text_blank(release_crop(host, "empty")))
  ignore(
    command(host, {
      "op": "fill",
      "selector": "#text-input",
      "value": "終了確認",
    }),
  )
  ignore(command(host, { "op": "click", "selector": "#task-start" }))
  ignore(command(host, { "op": "click", "selector": "#stop" }))
  ignore(
    command(host, {
      "op": "wait-text",
      "selector": "#status",
      "text": "Stopped.",
    }),
  )
  require(
    command(host, { "op": "disabled", "selector": "#text-input" }) ==
    Json::boolean(true),
    "release input remains enabled after stop",
  )
  let stopped = command(host, { "op": "image", "name": "stopped" })
  ignore(command(host, { "op": "late-input" }))
  require(
    command(host, { "op": "image", "name": "late" }) == stopped,
    "late work changed stopped release frame",
  )
  require(
    command(host, { "op": "no-probe" }) == Json::boolean(true),
    "release installed development control",
  )
  require(
    command(host, { "op": "excluded-assets" }) == Json::boolean(true),
    "release served comparison assets",
  )
  require(
    command(host, { "op": "errors" }) == Json::array([]),
    "release page errors",
  )
  return "{\"ordinary_ui\":true,\"rendered_edit_and_rpc\":true,\"resize\":true,\"stop\":true,\"development_excluded\":true}"
}

///|
#export_name("runRelease")
pub fn run_release_export(host : BrowserHost) -> @js_async.Promise[String] {
  @js_async.Promise::from_async(async fn() { run_release(host) })
}
