///|
pub struct SessionPolicy {
  mut next_id : Int64
  pending : Map[Int, Bool]
  mut closed : Bool
  mut identity : String
}

///|
#export_name("new_session_policy")
pub fn new_session_policy() -> SessionPolicy {
  { next_id: 1L, pending: {}, closed: false, identity: "", }
}

///|
#export_name("session_admission_error")
pub fn session_admission_error(state : SessionPolicy) -> String {
  if state.closed {
    "native session is closed"
  } else if state.pending.length() >= 16 {
    "native session pending limit exceeded"
  } else {
    ""
  }
}

///|
#export_name("allocate_session_id")
pub fn allocate_session_id(state : SessionPolicy) -> Int {
  if state.next_id > 2147483647L {
    return 0
  }
  let id = state.next_id.to_int()
  state.next_id += 1
  id
}

///|
#export_name("track_session_request")
pub fn track_session_request(state : SessionPolicy, id : Int) -> Unit {
  state.pending.set(id, true)
}

///|
#export_name("consume_session_response")
pub fn consume_session_response(state : SessionPolicy, id : Double) -> Bool {
  if id < 1 || id > 2147483647 || id.to_int().to_double() != id {
    return false
  }
  let key = id.to_int()
  if !state.pending.contains(key) {
    return false
  }
  state.pending.remove(key)
  true
}

///|
#export_name("close_session_policy")
pub fn close_session_policy(state : SessionPolicy) -> Unit {
  state.closed = true
  state.pending.clear()
}

///|
#export_name("accept_attachment_identity")
pub fn accept_attachment_identity(state : SessionPolicy, text : String) -> Bool {
  let value = @json.parse(text) catch { _ => return false }
  guard field(value, "session_id") is Json::String(identity) else {
    return false
  }
  if identity == "" || (state.identity != "" && state.identity != identity) {
    return false
  }
  state.identity = identity
  true
}
