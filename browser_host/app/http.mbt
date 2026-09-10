///|
priv struct HttpRequest {
  id : Int
  controller : @dom.AbortController
  mut reader : @dom.ReadableStreamDefaultReader?
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
    @dom.window().clear_timeout(id=timer)
  }
  self.controller.abort()
  if self.reader is Some(reader) {
    self.reader = None
    ignore(
      reader
      .cancel()
      .catch_(fn(_error) { @dom.JsValue::undefined() })
      .finally_(fn() { reader.release_lock() }),
    )
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
    ignore(@dom.document().dispatch_event(@dom.Event::new("metonic-rpc")))
  }
}

///|
fn HttpRequest::read(
  self : HttpRequest,
  status : Int,
  reader : @dom.ReadableStreamDefaultReader,
) -> Unit {
  ignore(
    reader
    .read()
    .then(fn(result) {
      if !self.live {
        return @dom.JsValue::undefined()
      }
      match result.done() {
        Some(true) => self.finish(status, None)
        Some(false) =>
          match result.value() {
            None => self.finish(status, Some(0))
            Some(value) => {
              let chunk : @dom.Uint8Array = value.unsafe_into()
              if chunk.length() >
                (65536 - self.bytes.length()).reinterpret_as_uint() {
                self.finish(status, Some(2))
              } else {
                for i = 0; i < chunk.length().reinterpret_as_int(); i = i + 1 {
                  self.bytes.push(chunk.get(i).unwrap())
                }
                self.read(status, reader)
              }
            }
          }
        None => self.finish(status, Some(0))
      }
      @dom.JsValue::undefined()
    })
    .catch_(fn(_error) {
      self.finish(status, Some(0))
      @dom.JsValue::undefined()
    }),
  )
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
  let input : @dom.HTMLInputElement = @dom.document()
    .get_element_by_id("rpc-user")
    .unsafe_into()
  let body = match @app.rpc_prepare(input.value()) {
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
    controller: @dom.AbortController::new(),
    reader: None,
    live: true,
    timer: None,
    bytes: [],
  }
  pending_http.val = Some(request)
  let timeout = @dom.Function::new(fn(_) {
    request.finish(0, Some(1))
    @dom.JsValue::undefined()
  })
  request.timer = Some(@dom.window().set_timeout(timeout, timeout=3000, []))
  let headers = [["Content-Type", "application/json"]]
  ignore(
    @dom.window()
    .fetch(
      "/rpc",
      init=@dom.RequestInit::new(
        method_="POST",
        headers~,
        body=@dom.XMLHttpRequestBodyInit::from(body),
        signal=request.controller.signal(),
      ),
    )
    .then(fn(response) {
      if !request.live {
        return @dom.JsValue::undefined()
      }
      let content_type = response.headers().get("Content-Type")
      if content_type != Some("application/json") &&
        content_type != Some("application/json; charset=utf-8") {
        request.finish(0, Some(3))
      } else {
        let status = response.status().reinterpret_as_int()
        match response.body() {
          None => request.finish(status, None)
          Some(stream) => {
            let reader = @dom.ReadableStreamDefaultReader::new(stream)
            request.reader = Some(reader)
            request.read(status, reader)
          }
        }
      }
      @dom.JsValue::undefined()
    })
    .catch_(fn(_error) {
      request.finish(0, Some(0))
      @dom.JsValue::undefined()
    }),
  )
  1
}
