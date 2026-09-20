///|
pub struct Transport {
  controller : @input_dom.AbortController
  mut reader : @input_dom.ReadableStreamDefaultReader?
}

///|
pub fn Transport::cleanup(self : Transport) -> Unit {
  self.controller.abort()
  if self.reader is Some(reader) {
    self.reader = None
    @async.run_async_main(async fn() {
      defer http_release_reader(reader)
      http_cancel_reader(reader) catch {
        _ => ()
      }
    })
  }
}

///|
pub impl @http.Http for Transport with fn post(self, request) {
  defer self.cleanup()
  if request.response_limit < 0 {
    return Err(@http.InvalidRequest)
  }
  try {
    let response = http_fetch(request, self.controller)
    let content_type = http_content_type(response)
    if !request.accepted_content_types.is_empty() &&
      !(content_type is Some(value) &&
      request.accepted_content_types.contains(value)) {
      return Err(@http.InvalidContentType)
    }
    let status = http_status(response)
    guard http_body(response) is Some(stream) else {
      return Ok({ status, content_type, body: b"", })
    }
    guard http_reader(stream) is Some(reader) else {
      return Err(@http.Transport)
    }
    self.reader = Some(reader)
    let bytes : Array[Byte] = []
    while true {
      let (done, chunk) = http_read(reader, self.controller)
      match done {
        Some(true) =>
          return Ok({ status, content_type, body: Bytes::from_array(bytes), })
        Some(false) => {
          guard chunk is Some(chunk) else { return Err(@http.Transport) }
          if chunk.length() > request.response_limit - bytes.length() {
            return Err(@http.ResponseTooLarge)
          }
          for byte in chunk {
            bytes.push(byte)
          }
        }
        None => return Err(@http.Transport)
      }
    } nobreak {
      Err(@http.Transport)
    }
  } catch {
    _ => Err(@http.Transport)
  }
}

///|
pub fn create() -> Transport {
  { controller: @input_dom.AbortController::new(), reader: None, }
}
