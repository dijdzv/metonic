///|
pub fn prepare(id : String) -> Result[@http.Request, String] {
  let body = @utf8.encode(
    @wire.request(@api.get_user(), @api.GetUserInput::{ id, }).stringify(),
  )
  if body.length() > 65536 {
    return Err("request_too_large")
  }
  Ok({
    path: "/rpc",
    content_type: "application/json",
    body,
    response_limit: 65536,
    accepted_content_types: [
      "application/json", "application/json; charset=utf-8",
    ],
  })
}

///|
pub fn decode(status : Int, bytes : Bytes) -> Result[@api.User, String] {
  if bytes.length() > 65536 {
    return Err("response_too_large")
  }
  let json = @wire.parse_bounded(@utf8.decode(bytes)) catch {
    _ => return Err("invalid_json")
  }
  match
    @wire.response(@api.get_user(), status, json, code => {
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
}

///|
pub async fn[H : @http.Http] load(
  http : H,
  id : String,
) -> Result[@api.User, String] {
  let request = match prepare(id) {
    Ok(request) => request
    Err(error) => return Err(error)
  }
  let response = match http.post(request) {
    Ok(response) => response
    Err(error) =>
      return Err(
        match error {
          @http.InvalidRequest => "transport_error"
          @http.Transport => "transport_error"
          @http.ResponseTooLarge => "response_too_large"
          @http.InvalidContentType => "invalid_content_type"
          @http.Timeout => "timeout"
        },
      )
  }
  if response.content_type != Some("application/json") &&
    response.content_type != Some("application/json; charset=utf-8") {
    return Err("invalid_content_type")
  }
  decode(response.status, response.body)
}
