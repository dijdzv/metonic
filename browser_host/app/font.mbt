///|
priv suberror FontFailure {
  FontFailure(String)
}

///|
impl Show for FontFailure with fn output(self, logger) {
  let FontFailure(message) = self
  logger.write_string(message)
}

///|
priv struct FontRequest {
  controller : @input_dom.AbortController
  mut reader : @input_dom.ReadableStreamDefaultReader?
  mut live : Bool
  bytes : Buffer
}

///|
let pending_font : Ref[FontRequest?] = Ref(None)

///|
fn FontRequest::cleanup(self : FontRequest) -> Unit {
  self.live = false
  self.controller.abort()
  self.bytes.reset()
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
fn FontRequest::check_live(self : FontRequest) -> Unit raise FontFailure {
  if !self.live {
    raise FontFailure("Font loading cancelled")
  }
}

///|
async fn FontRequest::load(
  self : FontRequest,
) -> @input_dom.ArrayBuffer raise Error {
  defer {
    if self.live {
      pending_font.val = None
    }
    self.cleanup()
  }
  let response = font_response(self.controller)
  self.check_live()
  let status = http_status(response)
  if status < 200 || status > 299 {
    raise FontFailure("Unable to fetch ./NotoSansJP.ttf (\{status})")
  }
  guard http_body(response) is Some(stream) else {
    raise FontFailure("Missing font response body")
  }
  guard http_reader(stream) is Some(reader) else {
    raise FontFailure("Unable to read font stream")
  }
  self.reader = Some(reader)
  while true {
    let (done, chunk) = http_read(reader)
    self.check_live()
    match done {
      Some(true) => break
      Some(false) => {
        guard chunk is Some(chunk) else {
          raise FontFailure("Missing font chunk")
        }
        if chunk.length() > 16777216 - self.bytes.length() {
          raise FontFailure("Font exceeds 16 MiB")
        }
        self.bytes.write_bytes(chunk)
        continue
      }
      None => raise FontFailure("Invalid font stream result")
    }
  }
  http_release_reader(reader)
  self.reader = None
  let buffer = @input_dom.ArrayBuffer::from_bytes(self.bytes.to_bytes())
  self.bytes.reset()
  let digest = font_digest(buffer)
  self.check_live()
  guard digest.to_bytes() is Some(bytes) else {
    raise FontFailure("Invalid font digest buffer")
  }
  let expected = "c2f3b4d463500a2ddcd3849cded1fceeb9fd6d1c32e6cbecd568453ba50fc68f"
  let hex = "0123456789abcdef"
  if bytes.length() != 32 {
    raise FontFailure("NotoSansJP.ttf SHA-256 mismatch")
  }
  for i in 0..<32 {
    let byte = bytes[i].to_int()
    if hex[byte >> 4] != expected[2 * i] ||
      hex[byte & 15] != expected[2 * i + 1] {
      raise FontFailure("NotoSansJP.ttf SHA-256 mismatch")
    }
  }
  buffer
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
#export_name("font_fetch")
pub fn font_fetch() -> FontPromise {
  font_fetch_cancel()
  let request = FontRequest::{
    controller: @input_dom.AbortController::new(),
    reader: None,
    live: true,
    bytes: Buffer(),
  }
  pending_font.val = Some(request)
  font_export(async fn() { request.load() })
}
