///|
async fn display_wait_observation(
  handle : @ui.Handle,
  reads : Ref[UInt],
) -> Unit {
  @async.with_timeout(5000, () => {
    (handle.apply)(@ui.Action::Activate)
    let id = (handle.retained_frame_id)()
    assert_eq((handle.wait_display)(0L, 100), "invalid_wait")
    assert_eq((handle.wait_display)(id, 0), "invalid_wait")
    assert_eq((handle.wait_display)(id + 1L, 100), "frame_not_submitted")
    assert_eq((handle.wait_display)(id, 25), "timeout")
    @async.with_task_group() <| group => {
      let first = group.spawn(() => (handle.wait_display)(id, 2000))
      let second = group.spawn(() => (handle.wait_display)(id, 35))
      @async.sleep(20)
      first.cancel()
      let canceled = try {
        ignore(first.wait())
        false
      } catch {
        error if @async.is_cancellation_error(error) => true
        error => raise error
      }
      assert_true(canceled)
      assert_eq(second.wait(), "timeout")
    }
    @async.sleep(20)
    let stopped = reads.val
    @async.sleep(40)
    assert_eq(reads.val, stopped)
    println("WINDOW_DISPLAY_WAIT_LIFECYCLE_OK")
    @async.with_task_group() <| group => {
      let _waiting = group.spawn(() => (handle.wait_display)(id, 2000))
      @async.sleep(20)
      (handle.apply)(@ui.Action::Close)
    }
  })
}
