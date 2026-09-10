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
async fn run_scene_gpu_lifecycle(
  host : BrowserHost,
  results : Array[Json],
) -> Unit {
  for target in ["js", "wasm-gc"] {
    ignore(command(host, { "op": "open" }))
    ignore(command(host, { "op": "goto", "target": "invalid" }))
    ignore(command(host, { "op": "settled-status" }))
    let observed = command(host, {
      "op": "scene-gpu-lifecycle",
      "target": Json::string(target),
    })
    let canceled = field(observed, "canceled").unwrap()
    require(
      int_field(canceled, "ready") == 0 && int_field(canceled, "created") == 0,
      "canceled GPU initialization allocated a buffer",
    )
    let replaced = field(observed, "replaced").unwrap()
    require(
      int_field(replaced, "ready") == 1 &&
      int_field(replaced, "oldReady") == 0 &&
      int_field(replaced, "obsoleteCreated") == 0,
      "obsolete GPU initialization replaced current resources",
    )
    require(
      int_field(replaced, "drawn") == 1 &&
      int_field(replaced, "writes") == 1 &&
      int_field(replaced, "draws") == 1,
      "current scene resources did not draw",
    )
    require(
      int_field(replaced, "afterDispose") == 0 &&
      int_field(replaced, "created") == 1 &&
      int_field(replaced, "destroyed") == 1,
      "scene disposal was not exactly once",
    )
    let rejected = field(observed, "rejected").unwrap()
    require(
      field(rejected, "rejected") == Some(Json::boolean(true)) &&
      int_field(rejected, "created") == 0,
      "pipeline rejection was lost",
    )
    let partial = field(observed, "partial").unwrap()
    require(
      field(partial, "rejected") == Some(Json::boolean(true)) &&
      int_field(partial, "created") == 1 &&
      int_field(partial, "destroyed") == 1,
      "partial scene resources leaked",
    )
    results.push({
      "name": Json::string(target + "-scene-gpu-lifecycle"),
      "observed": observed,
    })
    ignore(command(host, { "op": "close" }))
  }
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
  run_scene_gpu_lifecycle(host, results)
  Json::array(results).stringify()
}

///|
#export_name("runFailures")
pub fn run_failures_export(host : BrowserHost) -> @js_async.Promise[String] {
  @js_async.Promise::from_async(async fn() { run_failures(host) })
}

///|
async fn run_font_failures(host : BrowserHost) -> String {
  for target in ["js", "wasm-gc"] {
    run_font_failures_target(host, target)
  }
  Json::object({
    "font503": Json::boolean(true),
    "hashBad": Json::boolean(true),
    "sizeLimit": Json::boolean(true),
    "delayedStop": Json::boolean(true),
    "bodyStop": Json::boolean(true),
    "digestStop": Json::boolean(true),
    "replacement": Json::boolean(true),
  }).stringify()
}

///|
async fn run_font_failures_target(host : BrowserHost, target : String) -> Unit {
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
  ignore(command(host, { "op": "goto", "target": Json::string(target) }))
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
    command(host, {
      "op": "respond-route",
      "pattern": Json::string(pattern),
      "status": 200,
      "body": "x",
      "repeat": 16777217,
    }),
  )
  ignore(command(host, { "op": "reload" }))
  ignore(command(host, { "op": "settled-status" }))
  ignore(initialization_observation(host, "font-limit"))
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
  let replacement = command(host, {
    "op": "font-replace",
    "target": Json::string(target),
  })
  require(
    field(replacement, "oldRejected") == Some(Json::boolean(true)),
    "obsolete font was accepted",
  )
  require(
    field(replacement, "currentRejected") == Some(Json::boolean(true)),
    "replacement lost cancellation ownership",
  )
  require(
    int_field(replacement, "oldAborts") == 1,
    "obsolete font was not aborted",
  )
  require(
    int_field(replacement, "newAborts") == 1,
    "replacement font was not aborted",
  )
  require(
    int_field(replacement, "cancels") == 1,
    "replacement reader was not cancelled",
  )
  require(
    field(replacement, "locked") == Some(Json::boolean(false)),
    "replacement reader remained locked",
  )
  require(
    int_field(replacement, "freshBytes") == 9589900,
    "fresh font loading did not recover",
  )
  ignore(command(host, { "op": "close" }))
  ignore(command(host, { "op": "open" }))
  ignore(command(host, { "op": "stream-font" }))
  ignore(command(host, { "op": "goto", "target": Json::string(target) }))
  ignore(command(host, { "op": "stream-reading" }))
  ignore(command(host, { "op": "stop" }))
  let cleanup = command(host, { "op": "stream-cleaned" })
  require(int_field(cleanup, "aborts") == 1, "font fetch was not aborted once")
  require(
    int_field(cleanup, "cancels") == 1,
    "font stream was not cancelled once",
  )
  require(
    field(cleanup, "locked") == Some(Json::boolean(false)),
    "font reader remained locked",
  )
  ignore(initialization_observation(host, "font-body-stopped"))
  ignore(command(host, { "op": "close" }))
  ignore(command(host, { "op": "open" }))
  ignore(command(host, { "op": "hold-digest" }))
  ignore(command(host, { "op": "goto", "target": Json::string(target) }))
  ignore(command(host, { "op": "digest-held" }))
  ignore(command(host, { "op": "stop" }))
  ignore(command(host, { "op": "release-digest" }))
  ignore(command(host, { "op": "sleep", "milliseconds": 100 }))
  ignore(initialization_observation(host, "font-digest-stopped"))
  ignore(command(host, { "op": "close" }))
}

///|
#export_name("runFontFailures")
pub fn run_font_failures_export(
  host : BrowserHost,
) -> @js_async.Promise[String] {
  @js_async.Promise::from_async(async fn() { run_font_failures(host) })
}
