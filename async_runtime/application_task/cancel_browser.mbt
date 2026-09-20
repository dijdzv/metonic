///|
pub async fn cancel_and_wait(task : @async.Task[Unit]?) -> Unit {
  if task is Some(previous) {
    previous.cancel()
    previous.wait() catch {
      @async.TaskCancelled => ()
      error => raise error
    }
  }
  if @async.is_being_cancelled() {
    @async.pause()
  }
}
