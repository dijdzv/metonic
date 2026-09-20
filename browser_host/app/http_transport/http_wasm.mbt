///|
pub async fn http_fetch(
  request : @http.Request,
  controller : @input_dom.AbortController,
) -> @input_dom.Response raise Error {
  @input_binding.window()
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
pub fn http_content_type(response : @input_dom.Response) -> String? {
  response.headers().get("Content-Type")
}

///|
pub fn http_status(response : @input_dom.Response) -> Int {
  response.status().reinterpret_as_int()
}

///|
pub fn http_body(response : @input_dom.Response) -> @input_dom.ReadableStream? {
  response.body()
}

///|
pub fn http_reader(
  stream : @input_dom.ReadableStream,
) -> @input_dom.ReadableStreamDefaultReader? {
  Some(@input_dom.ReadableStreamDefaultReader::new(stream))
}

///|
pub async fn http_read(
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
pub async fn http_cancel_reader(
  reader : @input_dom.ReadableStreamDefaultReader,
) -> Unit raise Error {
  reader.cancel().wait()
}

///|
pub fn http_release_reader(
  reader : @input_dom.ReadableStreamDefaultReader,
) -> Unit {
  reader.release_lock()
}
