///|
async fn run_suite(host : BrowserHost, metadata : String) -> String {
  let config = @json.parse(metadata)
  let backend = string_field(config, "backend")
  require(
    backend == "default" || backend == "swiftshader",
    "unknown GPU backend",
  )
  let results : Array[Json] = []
  for target in ["js", "wasm-gc"] {
    let result = command(host, { "op": "scene", "target": Json::string(target) })
    require(string_field(result, "target") == target, "scene target mismatch")
    ignore(
      verify_browser_result({
        "backend": Json::string(backend),
        "result": result,
      }),
    )
    results.push(result)
  }
  let negative = command(host, { "op": "failures" })
  require(
    command(host, { "op": "default-target" }) == Json::string("wasm-gc"),
    "P0 default target mismatch",
  )
  for target in ["js", "wasm-gc"] {
    let flow = command(host, {
      "op": "editor-flow",
      "target": Json::string(target),
    })
    let preview = object_field(flow, "preview")
    require(
      string_field(preview, "text") == "A😀B",
      "preedit committed prematurely",
    )
    require(
      string_field(preview, "display") == "A日本B",
      "preedit missing from shared display",
    )
    let committed = object_field(flow, "committed")
    require(
      string_field(committed, "text") == "A日本B",
      "RPC or resize replaced committed text",
    )
    require(
      int_field(committed, "start") == 3 && int_field(committed, "end") == 3,
      "composition selection mismatch",
    )
    require(
      string_field(object_field(flow, "reset"), "text") ==
      "日本語の描画を確認します ABC 123",
      "reset lost initial editor",
    )
    require(
      string_field(object_field(flow, "stopped"), "text") == "",
      "late input revived disposed editor",
    )
  }
  for target in ["js", "wasm-gc"] {
    for
      scenario in [
        ("1", "\n月兎", 2),
        ("missing", "\nRPC: domain:not_found", 3),
      ] {
      let (user, expected, status) = scenario
      let result = command(host, {
        "op": "rpc",
        "target": Json::string(target),
        "user": Json::string(user),
        "text": "編集中 ABC 123",
      })
      require(
        string_field(result, "text") == "編集中 ABC 123",
        "RPC replaced editor contents",
      )
      require(string_field(result, "result") == expected, "RPC result mismatch")
      require(int_field(result, "status") == status, "RPC task status mismatch")
    }
  }
  for target in ["js", "wasm-gc"] {
    let result = command(host, {
      "op": "rpc",
      "target": Json::string(target),
      "user": "1",
      "text": Json::string(String::from_array(Array::make(1024, 'A'))),
      "after_text": "編集継続 日本語 ABC",
    })
    require(
      string_field(result, "text") == "編集継続 日本語 ABC",
      "maximum-length RPC prevented continued editing",
    )
    require(
      string_field(result, "result") == "\n月兎",
      "maximum-length RPC result mismatch",
    )
    require(
      int_field(result, "status") == 2,
      "maximum-length RPC stopped the app",
    )
  }
  let summaries : Array[Json] = []
  for target in ["js", "wasm-gc"] {
    for
      scenario in [("cancel", "", 4), ("replace", "\nRPC: domain:not_found", 3)] {
      let (mode, expected, status) = scenario
      let result = command(host, {
        "op": "rpc",
        "target": Json::string(target),
        "mode": Json::string(mode),
        "user": "1",
        "text": "編集中 ABC 123",
      })
      require(
        string_field(result, "text") == "編集中 ABC 123",
        "RPC cancellation replaced editor contents",
      )
      require(
        string_field(result, "result") == expected,
        "Canceled or replaced RPC changed result",
      )
      require(
        int_field(result, "status") == status,
        "RPC cancellation status mismatch",
      )
    }
  }
  let mut reference = ""
  for target in ["js", "wasm-gc"] {
    let result = command(host, {
      "op": "text",
      "target": Json::string(target),
      "reference": Json::string(reference),
    })
    let summary = object_field(result, "summary")
    require(string_field(summary, "target") == target, "text target mismatch")
    summaries.push(summary)
    reference = string_field(result, "reference")
    require(reference != "", "empty DPR reference")
  }
  require(
    command(host, { "op": "dpr", "reference": Json::string(reference) }) ==
    Json::boolean(true),
    "DPR scenario did not complete",
  )
  let font_failures = command(host, { "op": "font-failures" })
  let release = command(host, { "op": "release" })
  Json::object({
    "backend": Json::string(backend),
    "browser": Json::string(string_field(config, "browser")),
    "node": Json::string(string_field(config, "node")),
    "targets": Json::array(results),
    "negative": negative,
    "text": { "targets": Json::array(summaries), "dpr2": true },
    "textFailures": font_failures,
    "release": release,
  }).stringify()
}

///|
#export_name("runSuite")
pub fn run_suite_export(
  host : BrowserHost,
  metadata : String,
) -> @js_async.Promise[String] {
  @js_async.Promise::from_async(async fn() {
    run_suite(host, metadata) catch {
      VerifyFailure::Failure(message) => {
        println(message)
        raise VerifyFailure::Failure(message)
      }
      error => raise error
    }
  })
}
