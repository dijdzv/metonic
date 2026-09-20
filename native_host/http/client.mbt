///|
pub(all) struct NativeHttp {
  base : String
}

///|
pub impl @capability.Http for NativeHttp with fn post(self, request) {
  if request.response_limit < 0 {
    return Err(@capability.InvalidRequest)
  }
  try {
    let headers : Map[@wire_http.CaseInsensitiveString, String] = Map([])
    headers.set(
      @wire_http.CaseInsensitiveString("Content-Type"),
      request.content_type,
    )
    let client = @wire_http.Client(self.base)
    defer client.close()
    let response = client.post(
      request.path,
      request.body,
      extra_headers=headers,
    )
    let content_type = response.headers.get(
      @wire_http.CaseInsensitiveString("Content-Type"),
    )
    if !request.accepted_content_types.is_empty() &&
      !(content_type is Some(value) &&
      request.accepted_content_types.contains(value)) {
      return Err(@capability.InvalidContentType)
    }
    let bytes : Array[Byte] = []
    while true {
      let remaining = request.response_limit - bytes.length()
      let max_len = if remaining > 65536 {
        65536
      } else if remaining == 0 {
        1
      } else {
        remaining
      }
      guard client.read_some(max_len~) is Some(chunk) else { break }
      if chunk.length() > request.response_limit - bytes.length() {
        return Err(@capability.ResponseTooLarge)
      }
      for byte in chunk.iter() {
        bytes.push(byte)
      }
    }
    Ok({ status: response.code, content_type, body: Bytes::from_array(bytes), })
  } catch {
    error if @async.is_cancellation_error(error) => raise error
    _ => Err(@capability.Transport)
  }
}
