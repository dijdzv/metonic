///|
priv struct HttpRequest {
  id : Int
  controller : @input_dom.AbortController
  mut reader : @input_dom.ReadableStreamDefaultReader?
  mut live : Bool
  mut timer : Int?
  bytes : Array[Byte]
}

///|
let pending_http : Ref[HttpRequest?] = Ref(None)

///|
fn HttpRequest::cleanup(self : HttpRequest) -> Unit {
  self.live = false
  if self.timer is Some(timer) {
    self.timer = None
    http_clear_timeout(timer)
  }
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
fn HttpRequest::finish(
  self : HttpRequest,
  status : Int,
  failure : Int?,
) -> Unit {
  if !self.live {
    return
  }
  pending_http.val = None
  self.cleanup()
  let accepted = match failure {
    Some(code) => @app.rpc_transport_error(self.id, code)
    None => @app.rpc_accept(self.id, status, Bytes::from_array(self.bytes))
  }
  if accepted == 1 {
    http_notify()
  }
}

///|
async fn HttpRequest::perform(self : HttpRequest, body : String) -> Unit {
  let mut status = 0
  try {
    let response = http_fetch(body, self.controller)
    if !self.live {
      return
    }
    let content_type = http_content_type(response)
    if content_type != Some("application/json") &&
      content_type != Some("application/json; charset=utf-8") {
      self.finish(0, Some(3))
      return
    }
    status = http_status(response)
    guard http_body(response) is Some(stream) else {
      self.finish(status, None)
      return
    }
    guard http_reader(stream) is Some(reader) else {
      self.finish(status, Some(0))
      return
    }
    self.reader = Some(reader)
    while self.live {
      let (done, chunk) = http_read(reader)
      if !self.live {
        return
      }
      match done {
        Some(true) => {
          self.finish(status, None)
          return
        }
        Some(false) => {
          guard chunk is Some(chunk) else {
            self.finish(status, Some(0))
            return
          }
          if chunk.length() > 65536 - self.bytes.length() {
            self.finish(status, Some(2))
            return
          }
          for byte in chunk {
            self.bytes.push(byte)
          }
        }
        None => {
          self.finish(status, Some(0))
          return
        }
      }
    }
  } catch {
    _ => self.finish(status, Some(0))
  }
}

///|
#export_name("http_cancel")
pub fn http_cancel() -> Unit {
  if pending_http.val is Some(request) {
    pending_http.val = None
    request.cleanup()
  }
}

///|
#export_name("http_start")
pub fn http_start() -> Int {
  if inputs_composing() != 0 {
    return 0
  }
  guard input_query() is Some(input) else { return 0 }
  let body = match @app.rpc_prepare(InputElement::Query(input).value()) {
    Some(value) => value
    None => return 0
  }
  http_cancel()
  let id = @app.task_begin()
  if id < 0 {
    return 0
  }
  let request = HttpRequest::{
    id,
    controller: @input_dom.AbortController::new(),
    reader: None,
    live: true,
    timer: None,
    bytes: [],
  }
  pending_http.val = Some(request)
  match http_timeout(fn() { request.finish(0, Some(1)) }) {
    Some(timer) => request.timer = Some(timer)
    None => {
      request.finish(0, Some(0))
      return 1
    }
  }
  @async.run_async_main(async fn() { request.perform(body) })
  1
}
