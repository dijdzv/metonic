///|
fn number(value : Json, key : String) -> Json raise VerifyFailure {
  Json::number(int_field(value, key).to_double())
}

///|
async fn run_text(
  host : BrowserHost,
  target : String,
  reference : String,
) -> String {
  let initial = command(host, { "op": "crop" })
  ignore(text_initial(initial))
  let start = command(host, { "op": "counts" })
  let original = command(host, { "op": "original" })
  ignore(command(host, { "op": "fill", "value": "ABC 123" }))
  ignore(
    command(host, { "op": "wait-submit", "value": number(start, "submitted") }),
  )
  let changed = command(host, { "op": "crop" })
  let initial_data = string_field(initial, "data")
  ignore(
    text_compare({
      "actual": Json::string(string_field(changed, "data")),
      "expected": Json::string(initial_data),
      "equal": false,
    }),
  )
  ignore(command(host, { "op": "fill", "value": "" }))
  ignore(command(host, { "op": "sleep", "milliseconds": 200 }))
  ignore(text_blank(command(host, { "op": "crop" })))
  let blank = command(host, { "op": "counts" })
  ignore(command(host, { "op": "fill", "value": original }))
  let restored = command(host, { "op": "crop" })
  ignore(
    text_compare({
      "actual": Json::string(string_field(restored, "data")),
      "expected": Json::string(initial_data),
      "equal": true,
    }),
  )
  let restored_counts = command(host, { "op": "counts" })
  ignore(command(host, { "op": "key" }))
  ignore(command(host, { "op": "sleep", "milliseconds": 100 }))
  let moved = command(host, { "op": "counts" })
  ignore(
    verify_text_counts({
      "width": number(initial, "width"),
      "initialRenders": number(start, "renders"),
      "initialUploaded": number(start, "uploaded"),
      "renders": number(blank, "renders"),
      "uploaded": number(blank, "uploaded"),
      "restoredRenders": number(restored_counts, "renders"),
      "restoredUploaded": number(restored_counts, "uploaded"),
      "afterMoveRenders": number(moved, "renders"),
      "afterMoveUploaded": number(moved, "uploaded"),
    }),
  )
  ignore(command(host, { "op": "viewport", "width": 400, "height": 800 }))
  ignore(command(host, { "op": "wait-width", "value": number(start, "width") }))
  ignore(command(host, { "op": "viewport", "width": 1000, "height": 800 }))
  if reference != "" {
    ignore(
      text_compare({
        "actual": Json::string(initial_data),
        "expected": Json::string(reference),
        "equal": true,
      }),
    )
  }
  Json::object({
    "reference": Json::string(initial_data),
    "summary": {
      "target": Json::string(target),
      "width": number(start, "width"),
      "renders": number(blank, "renders"),
      "pixels": number(initial, "pixels"),
    },
  }).stringify()
}

///|
#export_name("runText")
pub fn run_text_export(
  host : BrowserHost,
  target : String,
  reference : String,
) -> @js_async.Promise[String] {
  @js_async.Promise::from_async(async fn() { run_text(host, target, reference) })
}

///|
async fn run_dpr(host : BrowserHost, reference : String) -> String {
  ignore(command(host, { "op": "goto", "target": "js" }))
  let status = command(host, { "op": "ready" })
  ignore(verify_ready({ "actual": status, "expected": "Ready: js" }))
  ignore(command(host, { "op": "align" }))
  let png = command(host, { "op": "screenshot" })
  ignore(dpr2({ "png": png, "reference": Json::string(reference) }))
  "true"
}

///|
#export_name("runDpr")
pub fn run_dpr_export(
  host : BrowserHost,
  reference : String,
) -> @js_async.Promise[String] {
  @js_async.Promise::from_async(async fn() { run_dpr(host, reference) })
}
