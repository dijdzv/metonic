///|
async fn http_fetch(
  body : String,
  controller : @input_dom.AbortController,
) -> @input_dom.Response raise Error {
  let options = @input_dom.RequestInit::{
    ..@input_dom.RequestInit::default(),
    method_: Some("POST"),
    headers: Some(
      @input_dom.HeadersInit::from_array_of_array_of_string([
        ["Content-Type", "application/json"],
      ]),
    ),
    body: Value(
      @input_dom.BodyInit::from_xml_http_request_body_init(
        @input_dom.XMLHttpRequestBodyInit::from_string(body),
      ),
    ),
    signal: Value(controller.get_signal()),
  }
  match input_window().fetch_with_string("/rpc", options).wait() {
    Ok(response) => response
    Err(_) => raise HttpBoundaryError
  }
}

///|
fn http_content_type(response : @input_dom.Response) -> String? {
  response.get_headers().get("Content-Type")
}

///|
fn http_status(response : @input_dom.Response) -> Int {
  response.get_status()
}

///|
fn http_body(response : @input_dom.Response) -> @input_dom.ReadableStream? {
  response.get_body()
}

///|
fn http_reader(
  stream : @input_dom.ReadableStream,
) -> @input_dom.ReadableStreamDefaultReader? {
  match @input_dom.ReadableStreamDefaultReader::new(stream) {
    Ok(reader) => Some(reader)
    Err(_) => None
  }
}

///|
async fn http_read(
  reader : @input_dom.ReadableStreamDefaultReader,
) -> (Bool?, Bytes?) raise Error {
  match reader.read().wait() {
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
async fn http_cancel_reader(
  reader : @input_dom.ReadableStreamDefaultReader,
) -> Unit raise Error {
  ignore(reader.cancel().wait())
}

///|
fn http_release_reader(reader : @input_dom.ReadableStreamDefaultReader) -> Unit {
  ignore(reader.release_lock())
}

///|
extern "js" fn http_timer_handler(callback : () -> Unit) -> @input_dom.Function =
  #| callback => callback

///|
fn http_timeout(callback : () -> Unit) -> Int? {
  match
    input_window().set_timeout_with_function(
      http_timer_handler(callback),
      3000,
      @input_dom.JsValue::undefined(),
    ) {
    Ok(timer) => Some(timer)
    Err(_) => None
  }
}

///|
fn http_clear_timeout(timer : Int) -> Unit {
  input_window().clear_timeout_with_id(timer)
}

///|
fn http_notify() -> Unit {
  ignore(
    input_document_target().dispatch_event(@input_dom.Event::new("metonic-rpc")),
  )
}

///|
priv suberror HttpBoundaryError
