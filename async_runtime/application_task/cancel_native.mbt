///|
pub async fn cancel_and_wait(task : @async.Task[Unit]?) -> Unit {
  if task is Some(previous) {
    previous.cancel()
    previous.wait() catch {
      error if @async.is_cancellation_error(error) => ()
      error => raise error
    }
  }
  // The awaited task's cancellation must not swallow this caller's cancellation.
  if @async.is_being_cancelled() {
    @async.pause()
  }
}
