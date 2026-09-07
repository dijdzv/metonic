///|
fn object_field(value : Json, key : String) -> Json raise VerifyFailure {
  match field(value, key) {
    Some(Json::Object(_) as object) => object
    _ => {
      fail("missing object " + key)
      Json::null()
    }
  }
}

///|
fn verify_state(request : Json) -> Json raise VerifyFailure {
  let stage = string_field(request, "stage")
  let before = object_field(request, "before")
  let after = object_field(request, "after")
  let submitted = int_field(before, "submitted")
  let next_submitted = int_field(after, "submitted")
  require(submitted >= 0 && next_submitted >= 0, "negative submitted count")
  require(submitted == next_submitted, "unexpected rendering after " + stage)
  if stage == "stopped" {
    let revision = int_field(before, "revision")
    let next_revision = int_field(after, "revision")
    require(revision >= 0 && next_revision >= 0, "negative revision")
    require(revision == next_revision, "state changed after stop")
  } else {
    require(stage == "idle", "unknown state verification stage")
  }
  Json::null()
}

///|
fn verify_initialization(request : Json) -> Json raise VerifyFailure {
  let stage = string_field(request, "stage")
  let status = string_field(request, "status")
  let expected = match stage {
    "invalid-target" => status.to_lower().contains("unknown target")
    "load-failure" => status.to_lower().contains("unable to fetch")
    "stopped" => status == "Stopped."
    "font503" => status.contains("Unable to fetch") && status.contains("503")
    "font-hash" => status.contains("SHA-256 mismatch")
    "font-stopped" => status == "Stopped."
    _ => false
  }
  require(expected, "unexpected initialization status: " + status)
  require(
    int_field(request, "submitted") == 0,
    "initialization submitted a frame",
  )
  match field(request, "errors") {
    Some(Json::Array(errors)) =>
      require(errors.is_empty(), "uncaught page error")
    _ => fail("missing page errors")
  }
  if stage.has_prefix("font") {
    require(
      field(request, "textDisabled") == Some(Json::boolean(true)),
      "text input must be disabled",
    )
    if stage == "font-stopped" {
      require(
        int_field(request, "beforeSubmitted") == 0,
        "frame submitted before font completed",
      )
      require(
        field(request, "stopDisabled") == Some(Json::boolean(true)),
        "stop must be disabled",
      )
    }
  } else if stage != "invalid-target" {
    require(
      field(request, "resetDisabled") == Some(Json::boolean(true)),
      "reset must be disabled",
    )
    require(
      field(request, "stopDisabled") == Some(Json::boolean(true)),
      "stop must be disabled",
    )
  }
  Json::null()
}

///|
fn verify_text_counts(request : Json) -> Json raise VerifyFailure {
  let width = int_field(request, "width")
  require(width > 0 && width <= 640, "text width")
  require(int_field(request, "initialRenders") == 1, "initial text renders")
  require(
    int_field(request, "initialUploaded") == width * 96 * 4,
    "initial text upload size",
  )
  let renders = int_field(request, "renders")
  let uploaded = int_field(request, "uploaded")
  let restored_renders = int_field(request, "restoredRenders")
  let restored_uploaded = int_field(request, "restoredUploaded")
  require(renders >= 0 && uploaded >= 0, "negative text counters")
  require(
    restored_renders > renders && restored_uploaded > uploaded,
    "restoring text did not render and upload",
  )
  require(
    int_field(request, "afterMoveRenders") == restored_renders,
    "movement rerasterized text",
  )
  require(
    int_field(request, "afterMoveUploaded") == restored_uploaded,
    "movement uploaded text",
  )
  Json::null()
}

///|
fn verify_ready(request : Json) -> Json raise VerifyFailure {
  require(
    string_field(request, "actual") == string_field(request, "expected"),
    "unexpected browser status",
  )
  Json::null()
}

///|
fn verify_browser_result(request : Json) -> Json raise VerifyFailure {
  let backend = string_field(request, "backend")
  require(
    backend == "default" || backend == "swiftshader",
    "unknown GPU backend",
  )
  let result = object_field(request, "result")
  match field(result, "pageerrors") {
    Some(Json::Array(errors)) =>
      require(errors.is_empty(), "uncaught page errors")
    _ => fail("missing page errors")
  }
  if backend == "swiftshader" {
    let adapter = object_field(result, "adapter")
    let description = match field(adapter, "description") {
      Some(Json::String(value)) => value
      _ => ""
    }
    let architecture = match field(adapter, "architecture") {
      Some(Json::String(value)) => value
      _ => ""
    }
    require(
      (description + " " + architecture).to_lower().contains("swiftshader"),
      "requested SwiftShader adapter not observed",
    )
  }
  Json::null()
}
