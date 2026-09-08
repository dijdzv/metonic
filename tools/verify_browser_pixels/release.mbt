///|
async fn release_crop(host : BrowserHost, name : String) -> Json {
  ignore(command(host, { "op": "focus", "selector": "#canvas" }))
  crop({ "png": command(host, { "op": "image", "name": name }), "width": 640 })
}

///|
async fn release_result(host : BrowserHost, name : String) -> Bytes {
  let image = decode_png(
    { "png": command(host, { "op": "image", "name": name }) },
    "png",
  )
  require(image.width >= 648 && image.height >= 136, "release result bounds")
  let pixels = Bytes::makei(640 * 32 * 4, index => {
    let pixel = index / 4
    image.data[((pixel / 640 + 104) * image.width + pixel % 640 + 8) * 4 +
    index % 4]
  })
  let mut ink = 0
  for pixel in 0..<(640 * 32) {
    if pixels[pixel * 4].to_int() < 128 &&
      pixels[pixel * 4 + 1].to_int() < 128 &&
      pixels[pixel * 4 + 2].to_int() < 128 {
      ink += 1
    }
  }
  require(ink > 20, "release HTTP result has no visible text")
  pixels
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
  verify_shared_view(host)
  ignore(
    command(host, {
      "op": "fill",
      "selector": "#text-input",
      "value": "配布版 ABC 😀",
    }),
  )
  let edited = release_crop(host, "edited")
  ignore(command(host, { "op": "click", "selector": "#task-start" }))
  ignore(
    command(host, {
      "op": "wait-text",
      "selector": "#task-state",
      "text": "Working…",
    }),
  )
  ignore(command(host, { "op": "click", "selector": "#task-cancel" }))
  ignore(
    command(host, {
      "op": "wait-text",
      "selector": "#task-state",
      "text": "Canceled",
    }),
  )
  ignore(command(host, { "op": "sleep", "milliseconds": 1100 }))
  ignore(
    command(host, {
      "op": "wait-text",
      "selector": "#task-state",
      "text": "Canceled",
    }),
  )
  ignore(
    command(host, { "op": "press", "selector": "#task-start", "key": "Enter" }),
  )
  ignore(
    command(host, {
      "op": "wait-text",
      "selector": "#task-state",
      "text": "Completed",
    }),
  )
  require(
    command(host, { "op": "value", "selector": "#text-input" }) ==
    Json::string("配布版 ABC 😀"),
    "task controls changed editor contents",
  )
  ignore(text_initial(edited))
  ignore(
    text_compare({
      "actual": field(edited, "data").unwrap(),
      "expected": field(initial, "data").unwrap(),
      "equal": false,
    }),
  )
  ignore(
    command(host, { "op": "press", "selector": "#rpc-load", "key": "Enter" }),
  )
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
      "equal": true,
    }),
  )
  let result_pixels = release_result(host, "result-row")
  let maximum_text = String::from_array(Array::make(1024, 'A'))
  ignore(
    command(host, {
      "op": "fill",
      "selector": "#text-input",
      "value": maximum_text,
    }),
  )
  let maximum_disabled = command(host, {
    "op": "disabled",
    "selector": "#text-input",
  })
  println(
    "release maximum-length editor disabled: " + maximum_disabled.stringify(),
  )
  require(
    maximum_disabled == Json::boolean(false),
    "HTTP result disabled editing of a valid maximum-length value",
  )
  require(
    release_result(host, "long-result-row") == result_pixels,
    "long editor changed result pixels",
  )
  ignore(command(host, { "op": "viewport", "width": 740 }))
  require(
    command(host, { "op": "value", "selector": "#text-input" }) ==
    Json::string(maximum_text),
    "resize changed maximum-length editor",
  )
  ignore(command(host, { "op": "viewport", "width": 1000 }))
  ignore(command(host, { "op": "viewport", "width": 600 }))
  verify_compact_tasks(host)
  ignore(command(host, { "op": "viewport", "width": 1000 }))
  ignore(
    command(host, {
      "op": "fill",
      "selector": "#text-input",
      "value": "配布版 ABC 😀",
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
  verify_rpc_failures(host)
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
  ignore(command(host, { "op": "fault-route" }))
  ignore(
    command(host, {
      "op": "fill",
      "selector": "#rpc-user",
      "value": "slow-body",
    }),
  )
  ignore(command(host, { "op": "click", "selector": "#rpc-load" }))
  fixture_activity(host, false)
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
  fixture_activity(host, true)
  ignore(command(host, { "op": "fault-route-off" }))
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
  return "{\"ordinary_ui\":true,\"rendered_edit_and_rpc\":true,\"resize\":true,\"stop\":true,\"development_excluded\":true,\"rpc_failures\":8,\"rpc_recovery\":8,\"rpc_cancel_replace\":2}"
}

///|
async fn verify_compact_tasks(host : BrowserHost) -> Unit {
  let before = command(host, { "op": "value", "selector": "#text-input" })
  ignore(command(host, { "op": "click", "selector": "#task-start" }))
  ignore(
    command(host, {
      "op": "wait-text",
      "selector": "#task-state",
      "text": "Working…",
    }),
  )
  ignore(command(host, { "op": "click", "selector": "#task-cancel" }))
  ignore(
    command(host, {
      "op": "wait-text",
      "selector": "#task-state",
      "text": "Canceled",
    }),
  )
  ignore(command(host, { "op": "sleep", "milliseconds": 1100 }))
  ignore(
    command(host, {
      "op": "wait-text",
      "selector": "#task-state",
      "text": "Canceled",
    }),
  )
  ignore(command(host, { "op": "image", "name": "compact-canceled" }))
  ignore(
    command(host, { "op": "press", "selector": "#task-start", "key": "Enter" }),
  )
  ignore(
    command(host, {
      "op": "wait-text",
      "selector": "#task-state",
      "text": "Completed",
    }),
  )
  require(
    command(host, { "op": "value", "selector": "#text-input" }) == before,
    "compact task changed editor",
  )
  verify_task_layout(host, true, "compact-completed")
  ignore(command(host, { "op": "canvas-height", "height": "360px" }))
  verify_task_layout(host, false, "height-restored")
  ignore(command(host, { "op": "canvas-height", "height": "" }))
  verify_task_layout(host, true, "height-compact")
}

///|
async fn verify_task_layout(
  host : BrowserHost,
  compact : Bool,
  name : String,
) -> Unit {
  let actual = command(host, { "op": "view-bounds" })
  guard actual is Json::Array(elements) && elements.length() == 4 else {
    fail("task bounds missing")
  }
  let start_y = if compact { 216 } else { 224 }
  let cancel_x = if compact { 288 } else { 8 }
  let cancel_y = if compact { 216 } else { 272 }
  near_coordinate(elements[2], "x", 8)
  near_coordinate(elements[2], "y", start_y.to_double())
  near_coordinate(elements[3], "x", cancel_x.to_double())
  near_coordinate(elements[3], "y", cancel_y.to_double())
  let image = decode_png(
    { "png": command(host, { "op": "image", "name": name }) },
    "png",
  )
  for
    entry in [
      (16, start_y + 4),
      (cancel_x + 8, cancel_y + 4),
      (8, if compact { 184 } else { 320 }),
    ] {
    let (x0, y0) = entry
    require(
      x0 + 100 <= image.width && y0 + 32 <= image.height,
      "task label outside canvas",
    )
    let mut ink = 0
    let mut white = 0
    for y in y0..<(y0 + 32) {
      for x in x0..<(x0 + 100) {
        let i = (y * image.width + x) * 4
        if image.data[i] < b'\x50' &&
          image.data[i + 1] < b'\x50' &&
          image.data[i + 2] < b'\x50' {
          ink += 1
        }
        if image.data[i] > b'\xF0' &&
          image.data[i + 1] > b'\xF0' &&
          image.data[i + 2] > b'\xF0' {
          white += 1
        }
      }
    }
    require(ink > 30 && white > 1000, "task GPU label missing at input bounds")
  }
}

///|
#export_name("runRelease")
pub fn run_release_export(host : BrowserHost) -> @js_async.Promise[String] {
  @js_async.Promise::from_async(async fn() { run_release(host) })
}
