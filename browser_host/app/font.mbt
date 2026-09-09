///|
priv struct FontRequest {
  controller : @dom.AbortController
  mut reader : @dom.ReadableStreamDefaultReader?
  mut live : Bool
  mut received : Int
  parts : Array[@dom.BlobPart]
}

///|
let pending_font : Ref[FontRequest?] = Ref(None)

///|
fn font_rejection(message : String) -> @dom.JsValue {
  let rejected : @dom.JsPromise[@dom.JsValue] = @dom.JsPromise::reject(
    @dom.TJsValue::to_js(message),
  )
  @dom.TJsValue::to_js(rejected)
}

///|
fn FontRequest::cleanup(self : FontRequest) -> Unit {
  self.live = false
  self.controller.abort()
  self.parts.clear()
  if self.reader is Some(reader) {
    self.reader = None
    ignore(
      reader
      .cancel()
      .catch_(fn(_) { @dom.JsValue::undefined() })
      .finally_(fn() { reader.release_lock() }),
    )
  }
}

///|
#export_name("font_fetch_cancel")
pub fn font_fetch_cancel() -> Unit {
  if pending_font.val is Some(request) {
    pending_font.val = None
    request.cleanup()
  }
}

///|
fn FontRequest::read(
  self : FontRequest,
  reader : @dom.ReadableStreamDefaultReader,
) -> @dom.JsPromise[@dom.JsValue] {
  reader
  .read()
  .then(fn(result) {
    if !self.live {
      return font_rejection("Font loading cancelled")
    }
    match result.done() {
      Some(true) => {
        reader.release_lock()
        self.reader = None
        let blob = @dom.Blob::new(blob_parts=self.parts)
        self.parts.clear()
        @dom.TJsValue::to_js(
          blob
          .array_buffer()
          .then(fn(buffer) {
            if !self.live {
              font_rejection("Font loading cancelled")
            } else {
              @dom.TJsValue::to_js(buffer)
            }
          }),
        )
      }
      Some(false) =>
        match result.value() {
          Some(value) => {
            let chunk : @dom.Uint8Array = value.unsafe_into()
            if chunk.length() > (16777216 - self.received).reinterpret_as_uint() {
              return font_rejection("Font exceeds 16 MiB")
            }
            self.received += chunk.length().reinterpret_as_int()
            let source : @dom.BufferSource = value.unsafe_into()
            self.parts.push(@dom.BlobPart::from(source))
            @dom.TJsValue::to_js(self.read(reader))
          }
          None => font_rejection("Missing font chunk")
        }
      None => font_rejection("Invalid font stream result")
    }
  })
}

///|
#export_name("font_fetch")
pub fn font_fetch() -> @dom.JsPromise[@dom.JsValue] {
  font_fetch_cancel()
  let request = FontRequest::{
    controller: @dom.AbortController::new(),
    reader: None,
    live: true,
    received: 0,
    parts: [],
  }
  pending_font.val = Some(request)
  @dom.window()
  .fetch(
    "./NotoSansJP.ttf",
    init=@dom.RequestInit::new(
      signal=request.controller.signal(),
      cache=NoCache,
    ),
  )
  .then(fn(response) {
    if !request.live {
      return font_rejection("Font loading cancelled")
    }
    if !response.ok() {
      return font_rejection(
        "Unable to fetch ./NotoSansJP.ttf (\{response.status()})",
      )
    }
    match response.body() {
      None => font_rejection("Missing font response body")
      Some(stream) => {
        let reader = @dom.ReadableStreamDefaultReader::new(stream)
        request.reader = Some(reader)
        @dom.TJsValue::to_js(request.read(reader))
      }
    }
  })
  .finally_(fn() {
    if request.live {
      pending_font.val = None
    }
    request.cleanup()
  })
}
