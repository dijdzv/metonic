///|
fn field(value : Json, name : String) -> Json {
  match value {
    Json::Object(fields) => fields.get(name).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn integer(value : Json, low : Double, high : Double) -> Bool {
  match value {
    Json::Number(number, ..) =>
      number >= low && number <= high && number.to_int64().to_double() == number
    _ => false
  }
}

///|
fn native_response(value : Json, window : Bool) -> Bool {
  if window {
    return field(value, "text") is Json::String(_) &&
      integer(field(value, "semantic_revision"), 0, 9007199254740991) &&
      integer(field(value, "frames"), 0, 9007199254740991) &&
      integer(field(value, "task_status"), 0, 5)
  }
  guard field(value, "state") is Json::Array(state) && state.length() == 8 else {
    return false
  }
  field(value, "version") == Json::number(1) &&
  integer(field(value, "id"), 1, 9007199254740991) &&
  field(value, "ok") is (Json::True | Json::False) &&
  (
    field(value, "ok") == Json::boolean(true) ||
    field(value, "error") is Json::String(_)
  ) &&
  state.all(item => integer(item, -9007199254740991, 9007199254740991)) &&
  integer(state[6], 1, 2048) &&
  integer(state[7], 1, 2048) &&
  integer(field(value, "frame"), 0, 9007199254740991)
}

///|
#export_name("validate_response")
pub fn validate_response(
  text : String,
  window : Bool,
  awaiting_ready : Bool,
) -> String {
  let value = @json.parse(text) catch {
    _ => return "invalid native session response"
  }
  let id = field(value, "id")
  if !window && awaiting_ready && id == Json::number(0) {
    return if field(value, "ok") == Json::boolean(true) &&
      field(value, "session_id") is Json::String(session) &&
      session != "" {
      ""
    } else {
      "invalid session ready response"
    }
  }
  if window && !(field(value, "error") is Json::String(_)) {
    return "invalid window response"
  }
  if !integer(id, 1, 9007199254740991) ||
    (!window && !(field(value, "ok") is (Json::True | Json::False))) {
    return "invalid response schema"
  }
  let success = if window {
    field(value, "error") == Json::string("")
  } else {
    field(value, "ok") == Json::boolean(true)
  }
  if !success {
    return if field(value, "error") is Json::String(_) {
      ""
    } else {
      "invalid response error"
    }
  }
  if native_response(
      if window {
        value
      } else {
        field(value, "response")
      },
      window,
    ) {
    ""
  } else {
    "invalid native response"
  }
}
