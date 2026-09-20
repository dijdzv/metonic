///|
priv struct BrowserHttp {
  controller : @input_dom.AbortController
  mut reader : @input_dom.ReadableStreamDefaultReader?
}

///|
priv struct PendingHttp {
  id : Int
  transport : BrowserHttp
  mut task : @async.Task[Unit]?
  mut live : Bool
}

///|
let pending_http : Ref[PendingHttp?] = Ref(None)

///|
fn BrowserHttp::cleanup(self : BrowserHttp) -> Unit {
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
impl @http.Http for BrowserHttp with fn post(self, request) {
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
#export_name("http_cancel")
pub fn http_cancel() -> Unit {
  if pending_http.val is Some(request) {
    pending_http.val = None
    request.live = false
    request.transport.cleanup()
    if request.task is Some(task) {
      @async.run_async_main(() => task.cancel())
    }
  }
}

///|
#export_name("http_start")
pub fn http_start() -> Int {
  if inputs_composing() != 0 {
    return 0
  }
  guard input_query() is Some(input) else { return 0 }
  let user_id = InputElement::Query(input).value()
  guard @app.rpc_prepare(user_id) is Some(_) else { return 0 }
  http_cancel()
  let id = @app.task_begin()
  if id < 0 {
    return 0
  }
  let request = PendingHttp::{
    id,
    transport: BrowserHttp::{
      controller: @input_dom.AbortController::new(),
      reader: None,
    },
    task: None,
    live: true,
  }
  pending_http.val = Some(request)
  @async.run_async_main(async fn() {
    @async.with_task_group(group => {
      let task = group.spawn(() => {
        if !request.live {
          return
        }
        let clock = BrowserClock::{
          wake: @cond_var.Cond(),
          timer: None,
          reset: false,
          ready: false,
        }
        let result = @user_load.load(
          @timed.TimedHttp::{
            transport: request.transport,
            clock,
            milliseconds: 3000,
          },
          user_id,
        )
        if !request.live {
          return
        }
        request.live = false
        if pending_http.val is Some(current) && current.id == request.id {
          pending_http.val = None
        }
        if @app.rpc_apply(id, result.map(user => user.name)) == 1 {
          http_notify()
        }
      })
      request.task = Some(task)
      task.wait() catch {
        @async.TaskCancelled => ()
        _ =>
          if request.live {
            request.live = false
            if pending_http.val is Some(current) && current.id == request.id {
              pending_http.val = None
            }
            if @app.rpc_transport_error(id, 0) == 1 {
              http_notify()
            }
          }
      }
    })
  })
  1
}
