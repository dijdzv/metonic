///|
pub async fn[G] dispatch(
  request : @task.Request,
  previous : @async.Task[Unit]?,
  group : @async.TaskGroup[G],
  post : (@task.Completion) -> Unit,
) -> @async.Task[Unit]? {
  request.invalidate()
  cancel_and_wait(previous)
  guard request.prepare() is Some(work) else { return None }
  Some(group.spawn(() => post(work.run(post_progress=post))))
}
