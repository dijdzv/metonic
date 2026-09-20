///|
let rpc_input : Ref[Array[Byte]] = Ref([])

///|
let rpc_expected : Ref[Int] = Ref(-1)

///|
let rpc_wire : Ref[Bytes] = Ref(b"")

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
  match rpc_prepare(user_id) {
    Some(request) => {
      rpc_wire.val = @utf8.encode(request)
      1
    }
    None => 0
  }
}

///|
pub fn rpc_prepare(user_id : String) -> String? {
  if @semantics.set_text(
      application.val.editor,
      application.val.query_input,
      user_id,
    ) !=
    "" {
    return None
  }
  match @user_load.prepare(user_id) {
    Ok(request) => Some(@utf8.decode(request.body)) catch { _ => None }
    Err(_) => None
  }
}

///|
#export_name("rpc_output_length")
pub fn rpc_output_length(kind : Int) -> Int {
  (if kind == 0 { rpc_wire.val } else { application.val.result_utf8 }).length()
}

///|
#export_name("rpc_output_byte")
pub fn rpc_output_byte(kind : Int, index : Int) -> Int {
  let bytes = if kind == 0 { rpc_wire.val } else { application.val.result_utf8 }
  if index < 0 || index >= bytes.length() {
    -1
  } else {
    bytes[index].to_int()
  }
}

///|
pub fn rpc_apply(id : Int, result : Result[String, String]) -> Int {
  if application.val.complete_user(id, result) {
    1
  } else {
    0
  }
}

///|
#export_name("rpc_response")
pub fn rpc_response(id : Int, status : Int) -> Int {
  let text = match rpc_decode() {
    Some(value) => value
    None => return rpc_apply(id, Err("invalid_json"))
  }
  rpc_response_text(id, status, text)
}

///|
pub fn rpc_accept(id : Int, status : Int, bytes : Bytes) -> Int {
  if bytes.length() > 65536 {
    return rpc_transport_error(id, 2)
  }
  let text = @utf8.decode(bytes) catch {
    _ => return rpc_apply(id, Err("invalid_json"))
  }
  rpc_response_text(id, status, text)
}

///|
fn rpc_response_text(id : Int, status : Int, text : String) -> Int {
  rpc_apply(
    id,
    @user_load.decode(status, @utf8.encode(text)).map(user => user.name),
  )
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
