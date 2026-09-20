///|
pub type FontPromise = @js_async.Promise[@input_dom.ArrayBuffer]

///|
#external
priv type FontCompletion

///|
fn FontCompletion::new() -> FontCompletion = "websys" "font_completion"

///|
fn FontCompletion::promise(self : FontCompletion) -> FontPromise = "websys" "font_promise"

///|
fn FontCompletion::resolve(
  self : FontCompletion,
  value : @input_dom.ArrayBuffer,
) -> Unit = "websys" "font_resolve"

///|
fn FontCompletion::reject(self : FontCompletion, message : String) -> Unit = "websys" "font_reject"

///|
fn font_export(
  task : async () -> @input_dom.ArrayBuffer raise Error,
) -> FontPromise {
  // The experimental WasmGC candidate cannot yet return a Promise from async.
  // Host settlement preserves the loader's Promise contract without another scheduler.
  let completion = FontCompletion::new()
  @async.run_async_main(async fn() {
    completion.resolve(task()) catch {
      error => completion.reject(error.to_string())
    }
  })
  completion.promise()
}

///|
async fn font_response(
  url : String,
  controller : @input_dom.AbortController,
) -> @input_dom.Response raise Error {
  @input_binding.window()
  .fetch(url, {
    method_: None,
    headers: None,
    body: Undefined,
    signal: Value(controller.signal()),
    cache: Some(NoCache),
  })
  .wait()
}

///|
async fn font_digest(
  buffer : @input_dom.ArrayBuffer,
) -> @input_dom.ArrayBuffer raise Error {
  @input_binding.window()
  .crypto()
  .subtle()
  .digest("SHA-256", Case1(buffer))
  .wait()
}
