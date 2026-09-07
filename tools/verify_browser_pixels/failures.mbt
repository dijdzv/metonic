///|
async fn initialization_observation(host : BrowserHost, stage : String) -> Json {
  let value = command(host, { "op": "observe" })
  match value {
    Json::Object(fields) => fields.set("stage", Json::string(stage))
    _ => fail("missing initialization observation")
  }
  ignore(verify_initialization(value))
  value
}

///|
async fn run_failures(host : BrowserHost) -> String {
  let results : Array[Json] = []
  for target in ["invalid", "js", "wasm-gc"] {
    ignore(command(host, { "op": "open" }))
    let stage = if target == "invalid" {
      "invalid-target"
    } else {
      "load-failure"
    }
    if target != "invalid" {
      for pattern in ["**/app.mjs", "**/app.wasm"] {
        ignore(
          command(host, { "op": "fail-route", "pattern": Json::string(pattern) }),
        )
      }
    }
    ignore(command(host, { "op": "goto", "target": Json::string(target) }))
    ignore(command(host, { "op": "settled-status" }))
    let observed = initialization_observation(host, stage)
    results.push({
      "name": Json::string(
        if target == "invalid" {
          stage
        } else {
          target + "-" + stage
        },
      ),
      "status": Json::string(string_field(observed, "status")),
      "frames": 0,
    })
    ignore(command(host, { "op": "close" }))
  }
  ignore(command(host, { "op": "open" }))
  ignore(command(host, { "op": "hold-route", "pattern": "**/app.wasm" }))
  ignore(command(host, { "op": "goto", "target": "wasm-gc" }))
  ignore(command(host, { "op": "request-seen" }))
  ignore(command(host, { "op": "stop" }))
  ignore(command(host, { "op": "settled-status" }))
  ignore(initialization_observation(host, "stopped"))
  ignore(command(host, { "op": "release" }))
  ignore(command(host, { "op": "network-idle" }))
  ignore(command(host, { "op": "sleep", "milliseconds": 500 }))
  ignore(initialization_observation(host, "stopped"))
  results.push({ "name": "wasm-init-race", "status": "Stopped.", "frames": 0 })
  ignore(command(host, { "op": "close" }))
  Json::array(results).stringify()
}

///|
#export_name("runFailures")
pub fn run_failures_export(host : BrowserHost) -> @js_async.Promise[String] {
  @js_async.Promise::from_async(async fn() { run_failures(host) })
}

///|
async fn run_font_failures(host : BrowserHost) -> String {
  let pattern = "**/NotoSansJP.ttf"
  ignore(command(host, { "op": "open" }))
  ignore(
    command(host, {
      "op": "respond-route",
      "pattern": Json::string(pattern),
      "status": 503,
      "body": "font unavailable",
    }),
  )
  ignore(command(host, { "op": "goto", "target": "js" }))
  ignore(command(host, { "op": "settled-status" }))
  ignore(initialization_observation(host, "font503"))
  ignore(command(host, { "op": "unroute", "pattern": Json::string(pattern) }))
  ignore(
    command(host, {
      "op": "respond-route",
      "pattern": Json::string(pattern),
      "status": 200,
      "body": "invalid font",
    }),
  )
  ignore(command(host, { "op": "reload" }))
  ignore(command(host, { "op": "settled-status" }))
  ignore(initialization_observation(host, "font-hash"))
  ignore(command(host, { "op": "unroute", "pattern": Json::string(pattern) }))
  ignore(
    command(host, { "op": "hold-route", "pattern": Json::string(pattern) }),
  )
  ignore(command(host, { "op": "reload" }))
  ignore(command(host, { "op": "request-seen" }))
  let before = command(host, { "op": "observe" })
  ignore(command(host, { "op": "stop" }))
  ignore(command(host, { "op": "release" }))
  ignore(command(host, { "op": "network-idle", "timeout": 5000 }))
  ignore(command(host, { "op": "sleep", "milliseconds": 500 }))
  let after = command(host, { "op": "observe" })
  match after {
    Json::Object(fields) => {
      fields.set("stage", Json::string("font-stopped"))
      fields.set(
        "beforeSubmitted",
        Json::number(int_field(before, "submitted").to_double()),
      )
    }
    _ => fail("font observation missing")
  }
  ignore(verify_initialization(after))
  ignore(command(host, { "op": "close" }))
  Json::object({
    "font503": Json::boolean(true),
    "hashBad": Json::boolean(true),
    "delayedStop": Json::boolean(true),
  }).stringify()
}

///|
#export_name("runFontFailures")
pub fn run_font_failures_export(
  host : BrowserHost,
) -> @js_async.Promise[String] {
  @js_async.Promise::from_async(async fn() { run_font_failures(host) })
}
