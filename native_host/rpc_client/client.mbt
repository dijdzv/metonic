///|
pub async fn get_user(base : String, id : String) -> Result[@api.User, String] {
  try {
    let result = @async.with_timeout_opt(3000, () => {
      let body = @wire.request(@api.get_user(), @api.GetUserInput::{ id, }).stringify()
      if @utf8.encode(body).length() > 65536 {
        return Err("request_too_large")
      }
      let headers : Map[@http.CaseInsensitiveString, String] = Map([])
      headers.set(
        @http.CaseInsensitiveString("Content-Type"),
        "application/json",
      )
      let client = @http.Client(base)
      defer client.close()
      let response = client.post("/rpc", body, extra_headers=headers)
      let content_type = response.headers.get(
        @http.CaseInsensitiveString("Content-Type"),
      )
      if content_type != Some("application/json") &&
        content_type != Some("application/json; charset=utf-8") {
        return Err("invalid_content_type")
      }
      let bytes : Array[Byte] = []
      while client.read_some(max_len=65537 - bytes.length()) is Some(chunk) {
        if bytes.length() + chunk.length() > 65536 {
          return Err("response_too_large")
        }
        for byte in chunk.iter() {
          bytes.push(byte)
        }
      }
      let json = @wire.parse_bounded(@utf8.decode(Bytes::from_array(bytes))) catch {
        _ => return Err("invalid_json")
      }
      match
        @wire.response(@api.get_user(), response.code, json, code => {
          if code == "not_found" {
            Some(@api.GetUserError::NotFound)
          } else {
            None
          }
        }) {
        Ok(user) => Ok(user)
        Err(@wire.CallError::Domain(_)) => Err("domain:not_found")
        Err(@wire.CallError::Protocol(code)) => Err("protocol:" + code)
        Err(@wire.CallError::Remote(code)) => Err("remote:" + code)
      }
    })
    result.unwrap_or(Err("timeout"))
  } catch {
    error if @async.is_cancellation_error(error) => raise error
    _ => Err("transport_error")
  }
}
