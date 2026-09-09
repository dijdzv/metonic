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
