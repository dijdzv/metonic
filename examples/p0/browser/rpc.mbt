///|
let rpc_input : Ref[Array[Byte]] = Ref([])

///|
let rpc_expected : Ref[Int] = Ref(-1)

///|
let rpc_wire : Ref[Bytes] = Ref(b"")

///|
let rpc_result : Ref[Bytes] = Ref(b"")

///|
#export_name("rpc_begin_input")
pub fn rpc_begin_input(length : Int) -> Int {
  rpc_input.val = []
  rpc_expected.val = -1
  if length < 0 || length > 65536 {
    return 0
  }
  rpc_expected.val = length
  1
}

///|
#export_name("rpc_put")
pub fn rpc_put(value : Int) -> Int {
  if value < 0 || value > 255 || rpc_input.val.length() >= rpc_expected.val {
    return 0
  }
  rpc_input.val.push(value.to_byte())
  1
}

///|
fn rpc_decode() -> String? {
  if rpc_input.val.length() != rpc_expected.val {
    return None
  }
  rpc_expected.val = -1
  Some(@utf8.decode(Bytes::from_array(rpc_input.val))) catch {
    _ => None
  }
}

///|
#export_name("rpc_request")
pub fn rpc_request() -> Int {
  rpc_wire.val = b""
  let user_id = match rpc_decode() {
    Some(value) => value
    None => return 0
  }
  let encoded = @utf8.encode(
    @wire.request(@api.get_user(), @api.GetUserInput::{ id: user_id, }).stringify(),
  )
  if encoded.length() > 65536 {
    return 0
  }
  rpc_wire.val = encoded
  1
}

///|
#export_name("rpc_output_length")
pub fn rpc_output_length(kind : Int) -> Int {
  (if kind == 0 { rpc_wire.val } else { rpc_result.val }).length()
}

///|
#export_name("rpc_output_byte")
pub fn rpc_output_byte(kind : Int, index : Int) -> Int {
  let bytes = if kind == 0 { rpc_wire.val } else { rpc_result.val }
  if index < 0 || index >= bytes.length() {
    -1
  } else {
    bytes[index].to_int()
  }
}

///|
fn rpc_apply(id : Int, result : Result[String, String]) -> Int {
  match result {
    Ok(name) =>
      if @task_scope.complete(taskScope.val, id, 0) {
        rpc_result.val = @utf8.encode("\n" + name)
        1
      } else {
        0
      }
    Err(error) =>
      if @task_scope.fail(taskScope.val, id, 1) {
        rpc_result.val = @utf8.encode("\nRPC: " + error)
        1
      } else {
        0
      }
  }
}

///|
#export_name("rpc_response")
#warnings("-deprecated")
pub fn rpc_response(id : Int, status : Int) -> Int {
  let text = match rpc_decode() {
    Some(value) => value
    None => return rpc_apply(id, Err("invalid_json"))
  }
  let json = @json.parse(text, max_nesting_depth=32) catch {
    _ => return rpc_apply(id, Err("invalid_json"))
  }
  let result = match
    @wire.response(@api.get_user(), status, json, code => {
      if code == "not_found" {
        Some(@api.GetUserError::NotFound)
      } else {
        None
      }
    }) {
    Ok(user) => Ok(user.name)
    Err(@wire.CallError::Domain(_)) => Err("domain:not_found")
    Err(@wire.CallError::Protocol(code)) => Err("protocol:" + code)
    Err(@wire.CallError::Remote(code)) => Err("remote:" + code)
  }
  rpc_apply(id, result)
}

///|
#export_name("rpc_transport_error")
pub fn rpc_transport_error(id : Int, code : Int) -> Int {
  rpc_apply(
    id,
    Err(
      match code {
        1 => "timeout"
        2 => "response_too_large"
        3 => "invalid_content_type"
        _ => "transport_error"
      },
    ),
  )
}
