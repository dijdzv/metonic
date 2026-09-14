///|
async fn display_wait_observation(
  handle : @ui.Handle,
  reads : Ref[UInt],
  injected : Ref[@gpu.DisplayObservation?],
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
    injected.val = Some(@gpu.DisplayObservation::Disjoint)
    assert_eq((handle.wait_display)(id, 100), "stale_display_epoch")
    injected.val = Some(@gpu.DisplayObservation::Sample(reads.val, 0U, 0L, 0U, 0U))
    assert_eq((handle.wait_display)(id, 100), "stale_display_epoch")
    assert_false((handle.capture_retained)(id).display_confirmed)

    injected.val = None
    (handle.apply)(@ui.Action::Activate)
    let reset_id = (handle.retained_frame_id)()
    assert_eq((handle.wait_display)(reset_id, 25), "timeout")
    injected.val = Some(@gpu.DisplayObservation::Sample(0U, 0U, 0L, 0U, 0U))
    assert_eq((handle.wait_display)(reset_id, 100), "stale_display_epoch")
    assert_false((handle.capture_retained)(reset_id).display_confirmed)

    injected.val = None
    (handle.apply)(@ui.Action::Activate)
    let before_resize = (handle.retained_frame_id)()
    let old_image = (handle.capture_retained)(before_resize)
    (handle.apply)(@ui.Action::Resize(800, 480))
    while (handle.inspect)().width != 800 || (handle.inspect)().height != 480 {
      @async.sleep(1)
    }
    let resized_id = (handle.retained_frame_id)()
    assert_true(resized_id > before_resize)
    assert_eq((handle.wait_display)(before_resize, 100), "stale_display_epoch")
    let resized = (handle.capture_retained)(resized_id)
    assert_true(resized.generation > old_image.generation)
    assert_false(resized.display_confirmed)
    assert_eq((handle.wait_display)(resized_id, 25), "timeout")
    println("WINDOW_DISPLAY_EPOCH_INVALIDATION_OK")
    println("WINDOW_DISPLAY_WAIT_LIFECYCLE_OK")
    @async.with_task_group() <| group => {
      let _waiting = group.spawn(() => (handle.wait_display)(resized_id, 2000))
      @async.sleep(20)
      (handle.apply)(@ui.Action::Close)
    }
  })
}
