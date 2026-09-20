///|
pub type FontPromise = @js_async.Promise[@input_dom.ArrayBuffer]

///|
fn font_export(
  task : async () -> @input_dom.ArrayBuffer raise Error,
) -> FontPromise {
  @js_async.Promise::from_async(task)
}

///|
async fn font_response(
  controller : @input_dom.AbortController,
) -> @input_dom.Response raise Error {
  let options = @input_dom.RequestInit::{
    ..@input_dom.RequestInit::default(),
    signal: Value(controller.get_signal()),
    cache: Some(NoCache),
  }
  match input_window().fetch_with_string("./NotoSansJP.ttf", options).wait() {
    Ok(response) => response
    Err(_) => raise FontFailure("Unable to fetch ./NotoSansJP.ttf")
  }
}

///|
async fn font_digest(
  buffer : @input_dom.ArrayBuffer,
) -> @input_dom.ArrayBuffer raise Error {
  input_window()
  .get_crypto()
  .get_subtle()
  .digest_with_string(
    "SHA-256",
    @input_dom.BufferSource::from_array_buffer(buffer),
  )
  .wait()
}
