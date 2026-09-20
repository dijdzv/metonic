///|
async fn http_fetch(
  request : @http.Request,
  controller : @input_dom.AbortController,
) -> @input_dom.Response raise Error {
  input_window()
  .fetch(request.path, {
    method_: Some("POST"),
    headers: Some(Case0([["Content-Type", request.content_type]])),
    body: Value(
      Case1(Case1(Case1(@input_dom.ArrayBuffer::from_bytes(request.body)))),
    ),
    signal: Value(controller.signal()),
    cache: None,
  })
  .wait(abort=() => controller.abort())
}

///|
fn http_content_type(response : @input_dom.Response) -> String? {
  response.headers().get("Content-Type")
}

///|
fn http_status(response : @input_dom.Response) -> Int {
  response.status().reinterpret_as_int()
}

///|
fn http_body(response : @input_dom.Response) -> @input_dom.ReadableStream? {
  response.body()
}

///|
fn http_reader(
  stream : @input_dom.ReadableStream,
) -> @input_dom.ReadableStreamDefaultReader? {
  Some(@input_dom.ReadableStreamDefaultReader::new(stream))
}

///|
async fn http_read(
  reader : @input_dom.ReadableStreamDefaultReader,
  controller : @input_dom.AbortController,
) -> (Bool?, Bytes?) raise Error {
  let result = reader.read().wait(abort=() => controller.abort())
  (
    result.done,
    match result.value {
      Some(value) => value.to_bytes()
      None => None
    },
  )
}

///|
async fn http_cancel_reader(
  reader : @input_dom.ReadableStreamDefaultReader,
) -> Unit raise Error {
  reader.cancel().wait()
}

///|
fn http_release_reader(reader : @input_dom.ReadableStreamDefaultReader) -> Unit {
  reader.release_lock()
}

///|
fn http_notify() -> Unit {
  ignore(
    input_document_target().dispatch_event(
      @input_dom.Event::new("metonic-rpc", {
        bubbles: None,
        cancelable: None,
        composed: None,
      }),
    ),
  )
}
