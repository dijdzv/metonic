///|
fn content_type(headers : Map[@http.CaseInsensitiveString, String]) -> Bool {
  match headers.get(@http.CaseInsensitiveString("Content-Type")) {
    Some(value) =>
      value == "application/json" || value == "application/json; charset=utf-8"
    None => false
  }
}

///|
pub async fn serve(
  endpoint : @wire.Endpoint,
  request : @http.Request,
  body : &@io.Reader,
  connection : @http.ServerConnection,
) -> Unit {
  let response = if request.meth != @http.Post {
    @wire.reject(405, "method_not_allowed")
  } else if request.path != "/rpc" {
    @wire.reject(404, "not_found")
  } else if !content_type(request.headers) {
    @wire.reject(415, "unsupported_media_type")
  } else {
    let read_result = @async.with_timeout_opt(2000, async fn() {
      let bytes : Array[Byte] = []
      let mut total = 0
      let mut done = false
      while !done {
        match body.read_some(max_len=65536 - total + 1) {
          None => done = true
          Some(chunk) => {
            if total + chunk.length() > 65536 {
              return None
            }
            for byte in chunk.iter() {
              bytes.push(byte)
            }
            total += chunk.length()
          }
        }
      }
      Some(bytes)
    })
    match read_result {
      None => @wire.reject(408, "request_timeout")
      Some(None) => @wire.reject(413, "request_too_large")
      Some(Some(bytes)) =>
        @wire.dispatch(endpoint, @utf8.decode(Bytes::from_array(bytes))) catch {
          _ => @wire.reject(400, "invalid_json")
        }
    }
  }
  let body_text = response.body.stringify()
  let headers : Map[@http.CaseInsensitiveString, String] = Map([])
  headers.set(@http.CaseInsensitiveString("Content-Type"), "application/json")
  headers.set(@http.CaseInsensitiveString("Connection"), "close")
  if @utf8.encode(body_text).length() > 65536 {
    let too_large = @wire.reject(500, "response_too_large").body.stringify()
    connection.send_response(
      500,
      "Internal Server Error",
      extra_headers=headers,
    )
    connection.write_string(too_large)
  } else {
    connection.send_response(response.status, "", extra_headers=headers)
    connection.write_string(body_text)
  }
  connection.end_response()
}
