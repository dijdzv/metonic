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
pub struct Loader {
  priv url : String
  priv expected : String
  priv pending_font : Ref[FontRequest?]
}

///|
fn FontRequest::cleanup(self : FontRequest) -> Unit {
  self.live = false
  self.controller.abort()
  self.bytes.reset()
  if self.reader is Some(reader) {
    self.reader = None
    @async.run_async_main(async fn() {
      defer @http_transport.http_release_reader(reader)
      @http_transport.http_cancel_reader(reader) catch {
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
  loader : Loader,
) -> @input_dom.ArrayBuffer raise Error {
  defer {
    if self.live {
      loader.pending_font.val = None
    }
    self.cleanup()
  }
  let response = font_response(loader.url, self.controller)
  self.check_live()
  let status = @http_transport.http_status(response)
  if status < 200 || status > 299 {
    raise FontFailure("Unable to fetch \{loader.url} (\{status})")
  }
  guard @http_transport.http_body(response) is Some(stream) else {
    raise FontFailure("Missing font response body")
  }
  guard @http_transport.http_reader(stream) is Some(reader) else {
    raise FontFailure("Unable to read font stream")
  }
  self.reader = Some(reader)
  while true {
    let (done, chunk) = @http_transport.http_read(reader, self.controller)
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
  @http_transport.http_release_reader(reader)
  self.reader = None
  let buffer = @input_dom.ArrayBuffer::from_bytes(self.bytes.to_bytes())
  self.bytes.reset()
  let digest = font_digest(buffer)
  self.check_live()
  guard digest.to_bytes() is Some(bytes) else {
    raise FontFailure("Invalid font digest buffer")
  }
  let expected = loader.expected
  let hex = "0123456789abcdef"
  if bytes.length() != 32 {
    raise FontFailure("\{loader.url} SHA-256 mismatch")
  }
  for i in 0..<32 {
    let byte = bytes[i].to_int()
    if hex[byte >> 4] != expected[2 * i] ||
      hex[byte & 15] != expected[2 * i + 1] {
      raise FontFailure("\{loader.url} SHA-256 mismatch")
    }
  }
  buffer
}

///|
pub fn Loader::cancel(loader : Loader) -> Unit {
  if loader.pending_font.val is Some(request) {
    loader.pending_font.val = None
    request.cleanup()
  }
}

///|
pub fn Loader::fetch(loader : Loader) -> FontPromise {
  loader.cancel()
  let request = FontRequest::{
    controller: @input_dom.AbortController::new(),
    reader: None,
    live: true,
    bytes: Buffer(),
  }
  loader.pending_font.val = Some(request)
  font_export(async fn() { request.load(loader) })
}

///|
pub fn create(url : String, sha256 : String) -> Loader? {
  if url.is_empty() || sha256.length() != 64 {
    return None
  }
  for unit in sha256.iter() {
    if !(unit >= '0' && unit <= '9') && !(unit >= 'a' && unit <= 'f') {
      return None
    }
  }
  Some({ url, expected: sha256, pending_font: Ref(None), })
}
