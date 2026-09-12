///|
#export_name("window_request_timeout")
pub fn window_request_timeout(text : String, ordinary_ms : Int) -> Int {
  let value = @json.parse(text) catch { _ => return ordinary_ms }
  if field(value, "op") != Json::string("wait_semantic") ||
    !integer(field(value, "semantic_revision"), 0, 2147483647) ||
    !integer(field(value, "timeout_ms"), 1, 60000) {
    return ordinary_ms
  }
  guard field(value, "timeout_ms") is Json::Number(timeout, ..) else {
    return ordinary_ms
  }
  ordinary_ms.max(timeout.to_int() + 1000)
}

///|
#export_name("validate_request")
pub fn validate_request(
  text : String,
  window : Bool,
  id : Int,
  op : String,
) -> String {
  if @utf8.encode(text).length() > 4095 {
    return "native session request exceeds 4095 bytes"
  }
  let value = @json.parse(text) catch {
    _ => return "invalid native session request"
  }
  if !integer(field(value, "id"), 1, 2147483647) ||
    !(field(value, "op") is Json::String(_)) ||
    (!window && !(field(value, "args") is Json::Object(_))) ||
    field(value, "id") != Json::number(id.to_double()) ||
    field(value, "op") != Json::string(op) {
    return "invalid native session request"
  }
  ""
}
