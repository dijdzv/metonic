///|
#external
type BrowserHost

///|
extern "js" fn call_host(
  host : BrowserHost,
  request : String,
) -> @js_async.Promise[String] =
  #| async (host, request) => JSON.stringify(await host(JSON.parse(request)))

///|
async fn command(host : BrowserHost, request : Json) -> Json {
  @json.parse(@js_async.Promise::wait(call_host(host, request.stringify()))) catch {
    error => {
      let context : Map[String, Json] = Map([])
      for key in ["op", "target", "selector", "name"] {
        if field(request, key) is Some(Json::String(value)) {
          context.set(
            key,
            Json::string(value[:value.length().min(128)].to_owned()),
          )
        }
      }
      let detail = match error {
        VerifyFailure::Failure(message) => message
        other => other.to_string()
      }
      raise VerifyFailure::Failure(
        "browser operation " + Json::object(context).stringify() + ": " + detail,
      )
    }
  }
}

///|
async fn capture_scene(
  host : BrowserHost,
  stage : String,
  previous : Json,
) -> Json {
  let capture = command(host, { "op": "capture", "name": Json::string(stage) })
  let request = object_field(capture, "capture")
  match request {
    Json::Object(fields) => {
      fields.set("stage", Json::string(stage))
      fields.set("previous", previous)
    }
    _ => fail("capture object missing")
  }
  scene(request)
}

///|
async fn wait_increment(
  host : BrowserHost,
  before : Json,
  key : String,
) -> Unit {
  ignore(
    command(host, {
      "op": "wait-increment",
      "key": Json::string(key),
      "value": Json::number(int_field(before, key).to_double()),
    }),
  )
}

///|
async fn run_scene(host : BrowserHost, target : String) -> String {
  require(target == "js" || target == "wasm-gc", "unknown scenario target")
  let images : Map[String, Json] = Map([])
  let initial = capture_scene(host, "initial", Json::null())
  images.set("initial", initial)
  let before = command(host, { "op": "diagnostic" })
  ignore(
    command(host, {
      "op": "click",
      "x": Json::number((int_field(initial, "x") + 60).to_double()),
      "y": Json::number((int_field(initial, "y") + 36).to_double()),
    }),
  )
  wait_increment(host, before, "revision")
  wait_increment(host, before, "submitted")
  let active = capture_scene(host, "active", initial)
  images.set("active", active)
  let before = command(host, { "op": "diagnostic" })
  ignore(command(host, { "op": "key" }))
  wait_increment(host, before, "revision")
  wait_increment(host, before, "submitted")
  images.set("moved", capture_scene(host, "moved", active))
  let before = command(host, { "op": "diagnostic" })
  ignore(command(host, { "op": "viewport", "width": 800, "height": 700 }))
  ignore(
    command(host, {
      "op": "wait-dimensions",
      "value": Json::string(string_field(before, "dimensions")),
    }),
  )
  wait_increment(host, before, "submitted")
  images.set("resized", capture_scene(host, "resized", Json::null()))
  let idle_before = command(host, { "op": "diagnostic" })
  ignore(command(host, { "op": "sleep", "milliseconds": 250 }))
  let idle_after = command(host, { "op": "diagnostic" })
  ignore(
    verify_state({ "stage": "idle", "before": idle_before, "after": idle_after }),
  )
  let before = command(host, { "op": "diagnostic" })
  ignore(command(host, { "op": "button", "selector": "#reset" }))
  ignore(
    command(host, {
      "op": "status",
      "expected": Json::string("Ready: " + target),
    }),
  )
  wait_increment(host, before, "submitted")
  images.set("reset", capture_scene(host, "reset", Json::null()))
  ignore(command(host, { "op": "button", "selector": "#stop" }))
  ignore(command(host, { "op": "status", "expected": "Stopped." }))
  let stopped = command(host, { "op": "diagnostic" })
  ignore(command(host, { "op": "click", "x": 10, "y": 10 }))
  ignore(command(host, { "op": "key" }))
  ignore(command(host, { "op": "viewport", "width": 700, "height": 600 }))
  ignore(command(host, { "op": "sleep", "milliseconds": 250 }))
  let after = command(host, { "op": "diagnostic" })
  ignore(
    verify_state({ "stage": "stopped", "before": stopped, "after": after }),
  )
  Json::object({
    "images": Json::object(images),
    "idle": {
      "before": idle_before,
      "after": idle_after,
      "unchanged": Json::boolean(idle_before == idle_after),
    },
    "stop": { "before": stopped, "after": after, "frameUnchanged": true },
  }).stringify()
}

///|
#export_name("runScene")
pub fn run_scene_export(
  host : BrowserHost,
  target : String,
) -> @js_async.Promise[String] {
  @js_async.Promise::from_async(async fn() { run_scene(host, target) })
}
