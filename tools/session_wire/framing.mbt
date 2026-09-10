///|
pub struct ResponseFramer {
  parts : Array[String]
  limit : Int
  mut bytes : Int
  mut error : String
}

///|
#export_name("new_response_framer")
pub fn new_response_framer() -> ResponseFramer {
  { parts: [], limit: 32 * 1024 * 1024, bytes: 0, error: "", }
}

///|
#export_name("clear_response_framer")
pub fn clear_response_framer(state : ResponseFramer) -> Unit {
  state.parts.clear()
  state.bytes = 0
}

///|
#export_name("response_framing_error")
pub fn response_framing_error(state : ResponseFramer) -> String {
  state.error
}

///|
#export_name("append_response_text")
pub fn append_response_text(
  state : ResponseFramer,
  decoded : String,
) -> Array[String] {
  let lines : Array[String] = []
  if state.error != "" {
    return lines
  }
  let parts = decoded.split("\n").to_array()
  for i = 0; i < parts.length(); i = i + 1 {
    let part = parts[i].to_owned()
    let size = @utf8.encode(part).length()
    if size > state.limit - state.bytes {
      state.error = "native session response line exceeds 32MiB"
      clear_response_framer(state)
      return lines
    }
    if size > 0 {
      state.parts.push(part)
    }
    state.bytes += size
    if i < parts.length() - 1 {
      let text = state.parts.join("")
      clear_response_framer(state)
      lines.push(
        if text.has_suffix("\r") {
          text[:text.length() - 1].to_owned()
        } else {
          text
        },
      )
    }
  }
  lines
}

///|
#export_name("finish_response_framer")
pub fn finish_response_framer(state : ResponseFramer) -> String {
  if state.error == "" && state.bytes > 0 {
    state.error = "truncated native session response line"
  }
  clear_response_framer(state)
  state.error
}
