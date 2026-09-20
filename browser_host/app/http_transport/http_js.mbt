///|
pub async fn http_fetch(
  request : @http.Request,
  controller : @input_dom.AbortController,
) -> @input_dom.Response raise Error {
  let options = @input_dom.RequestInit::{
    ..@input_dom.RequestInit::default(),
    method_: Some("POST"),
    headers: Some(
      @input_dom.HeadersInit::from_array_of_array_of_string([
        ["Content-Type", request.content_type],
      ]),
    ),
    body: Value(
      @input_dom.BodyInit::from_xml_http_request_body_init(
        @input_dom.XMLHttpRequestBodyInit::from_buffer_source(
          @input_dom.BufferSource::from_array_buffer(
            @input_dom.ArrayBuffer::from_bytes(request.body),
          ),
        ),
      ),
    ),
    signal: Value(controller.get_signal()),
  }
  match
    @input_binding.window()
    .fetch_with_string(request.path, options)
    .wait(abort_controller=http_async_controller(controller)) {
    Ok(response) => response
    Err(_) => raise HttpBoundaryError
  }
}

///|
pub fn http_content_type(response : @input_dom.Response) -> String? {
  response.get_headers().get("Content-Type")
}

///|
pub fn http_status(response : @input_dom.Response) -> Int {
  response.get_status()
}

///|
pub fn http_body(response : @input_dom.Response) -> @input_dom.ReadableStream? {
  response.get_body()
}

///|
pub fn http_reader(
  stream : @input_dom.ReadableStream,
) -> @input_dom.ReadableStreamDefaultReader? {
  match @input_dom.ReadableStreamDefaultReader::new(stream) {
    Ok(reader) => Some(reader)
    Err(_) => None
  }
}

///|
pub async fn http_read(
  reader : @input_dom.ReadableStreamDefaultReader,
  controller : @input_dom.AbortController,
) -> (Bool?, Bytes?) raise Error {
  match reader.read().wait(abort_controller=http_async_controller(controller)) {
    Ok(result) =>
      (
        result.done,
        match result.value {
          Some(value) => value.to_bytes()
          None => None
        },
      )
    Err(_) => raise HttpBoundaryError
  }
}

///|
pub async fn http_cancel_reader(
  reader : @input_dom.ReadableStreamDefaultReader,
) -> Unit raise Error {
  ignore(reader.cancel().wait())
}

///|
pub fn http_release_reader(
  reader : @input_dom.ReadableStreamDefaultReader,
) -> Unit {
  ignore(reader.release_lock())
}

///|
priv suberror HttpBoundaryError

///|
// Both libraries represent the same host AbortController; a new controller would not abort Fetch.
extern "js" fn http_async_controller(
  controller : @input_dom.AbortController,
) -> @js_async.AbortController =
  #| controller => controller
