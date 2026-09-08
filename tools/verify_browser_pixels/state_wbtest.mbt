///|
test "idle and stopped verification rejects state regressions and malformed counters" {
  for stage in ["idle", "stopped"] {
    let request : Json = {
      "action": "state",
      "stage": Json::string(stage),
      "before": { "submitted": 3, "revision": 2 },
      "after": { "submitted": 3, "revision": 2 },
    }
    ignore(verify_checked(request.stringify()))
  }
  for
    request in [
      "{\"action\":\"state\",\"stage\":\"idle\",\"before\":{\"submitted\":3},\"after\":{\"submitted\":4}}",
      "{\"action\":\"state\",\"stage\":\"stopped\",\"before\":{\"submitted\":3,\"revision\":2},\"after\":{\"submitted\":3,\"revision\":3}}",
      "{\"action\":\"state\",\"stage\":\"idle\",\"before\":{\"submitted\":-1},\"after\":{\"submitted\":-1}}",
      "{\"action\":\"state\",\"stage\":\"idle\",\"before\":{\"submitted\":1.5},\"after\":{\"submitted\":1.5}}",
      "{\"action\":\"state\",\"stage\":\"stopped\",\"before\":{\"submitted\":3},\"after\":{\"submitted\":3}}",
      "{\"action\":\"state\",\"stage\":\"unknown\",\"before\":{\"submitted\":3},\"after\":{\"submitted\":3}}",
    ] {
    let response = @json.parse(verify(request))
    assert_eq(field(response, "ok"), Some(Json::boolean(false)))
  }
}

///|
test "initialization failures reject missing evidence and post-stop rendering" {
  fn observation() -> Json {
    {
      "action": "initialization",
      "stage": "stopped",
      "status": "Stopped.",
      "submitted": 0,
      "errors": [],
      "resetDisabled": true,
      "stopDisabled": true,
    }
  }
  ignore(verify_checked(observation().stringify()))
  for
    pair in [
      ("stage", Json::string("unknown")),
      ("status", Json::string("Ready: wasm-gc")),
      ("submitted", Json::number(1)),
      ("submitted", Json::string("0")),
      ("errors", Json::array([Json::string("late failure")])),
      ("errors", Json::null()),
      ("resetDisabled", Json::boolean(false)),
      ("stopDisabled", Json::null()),
    ] {
    let (key, value) = pair
    let request = observation()
    match request {
      Json::Object(fields) => fields.set(key, value)
      _ => ()
    }
    assert_eq(
      field(@json.parse(verify(request.stringify())), "ok"),
      Some(Json::boolean(false)),
    )
  }
  for
    pair in [
      ("invalid-target", "Unknown target: invalid"),
      ("load-failure", "Unable to fetch app.wasm: 503"),
    ] {
    let (stage, status) = pair
    let request = observation()
    match request {
      Json::Object(fields) => {
        fields.set("stage", Json::string(stage))
        fields.set("status", Json::string(status))
      }
      _ => ()
    }
    ignore(verify_checked(request.stringify()))
  }
}

///|
test "font stop requires disabled input and zero frames before and after release" {
  let request : Json = {
    "action": "initialization",
    "stage": "font-stopped",
    "status": "Stopped.",
    "submitted": 0,
    "beforeSubmitted": 0,
    "errors": [],
    "textDisabled": true,
    "stopDisabled": true,
  }
  ignore(verify_checked(request.stringify()))
  match request {
    Json::Object(fields) => fields.set("beforeSubmitted", Json::number(1))
    _ => ()
  }
  assert_eq(
    field(@json.parse(verify(request.stringify())), "ok"),
    Some(Json::boolean(false)),
  )
}

///|
test "moving the rectangle must not upload the restored text again" {
  let request : Json = {
    "action": "text_counts",
    "width": 100,
    "initialRenders": 1,
    "initialUploaded": 54400,
    "renders": 3,
    "uploaded": 163200,
    "restoredRenders": 4,
    "restoredUploaded": 217600,
    "afterMoveRenders": 4,
    "afterMoveUploaded": 217600,
  }
  ignore(verify_checked(request.stringify()))
  match request {
    Json::Object(fields) =>
      fields.set("afterMoveUploaded", Json::number(272000))
    _ => ()
  }
  assert_eq(
    field(@json.parse(verify(request.stringify())), "ok"),
    Some(Json::boolean(false)),
  )
}
