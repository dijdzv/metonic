///|
async fn capture_observation(handle : @ui.Handle) -> Unit {
  @async.with_timeout(10000, () => {
    let revision = (handle.inspect)().semantic_revision
    assert_eq((handle.wait_semantic)(revision, 100), "")
    assert_eq((handle.wait_semantic)(-1, 100), "invalid_wait")
    assert_eq((handle.wait_semantic)(revision, 0), "invalid_wait")
    assert_eq((handle.wait_semantic)(revision + 1, 10), "timeout")
    @async.with_task_group() <| group => {
      let waiting = group.spawn(() => (handle.wait_semantic)(revision + 1, 1000))
      @async.pause()
      assert_eq((handle.edit)(Some("wait"), None), "")
      assert_eq(waiting.wait(), "")
      let canceled = group.spawn(() => (handle.wait_semantic)(2147483647, 1000))
      @async.pause()
      canceled.cancel()
      let canceled_cleanly = try {
        ignore(canceled.wait())
        false
      } catch {
        error if @async.is_cancellation_error(error) => true
        error => raise error
      }
      assert_true(canceled_cleanly)
    }
    @async.with_task_group() <| group => {
      let before = (handle.inspect)()
      let pending = group.spawn(() => (handle.capture)())
      @async.pause()
      (handle.apply)(@ui.Action::Move(7, 0))
      let image = pending.wait()
      let after = (handle.inspect)()
      assert_true(after.frames > image.frame)
      assert_eq(after.x, before.x + 7)
      assert_eq(image.state.frames, image.frame)
      assert_eq(image.state.x, before.x)
      assert_eq(image.state.scene_revision, before.scene_revision)
      assert_eq(image.width, image.state.width)
      assert_eq(image.height, image.state.height)
      assert_eq(image.pixels.length(), image.width * image.height * 4)
    }
    let retained_id = (handle.retained_frame_id)()
    assert_true(retained_id > 0L)
    let original = (handle.capture_retained)(retained_id)
    (handle.apply)(@ui.Action::Activate)
    let next_id = (handle.retained_frame_id)()
    assert_true(next_id > retained_id)
    let retained = (handle.capture_retained)(retained_id)
    assert_eq(retained.id, original.id)
    assert_eq(retained.generation, original.generation)
    assert_eq(retained.width, original.width)
    assert_eq(retained.height, original.height)
    assert_eq(retained.pixels, original.pixels)
    assert_eq(retained.display_scale, original.display_scale)
    assert_true(original.display_scale is Some(scale) && scale > 0.0)
    let next = (handle.capture_retained)(next_id)
    assert_true(next.pixels != original.pixels)
    (handle.apply)(@ui.Action::Move(7, 0))
    let evicted = try {
      ignore((handle.capture_retained)(retained_id))
      false
    } catch {
      @gpu.RetainedFrameError::FrameEvicted => true
      error => raise error
    }
    assert_true(evicted)
    let invalid = try {
      ignore((handle.capture_retained)(0L))
      false
    } catch {
      @gpu.RetainedFrameError::InvalidFrame => true
      error => raise error
    }
    assert_true(invalid)
    let future = try {
      ignore((handle.capture_retained)((handle.retained_frame_id)() + 1L))
      false
    } catch {
      @gpu.RetainedFrameError::FrameNotSubmitted => true
      error => raise error
    }
    assert_true(future)
    let latest = (handle.capture_retained)((handle.retained_frame_id)())
    assert_true(latest.id > next_id)
    @async.with_task_group() <| group => {
      let canceled = group.spawn(() => (handle.capture_retained)(latest.id))
      @async.pause()
      canceled.cancel()
      let canceled_cleanly = try {
        ignore(canceled.wait())
        false
      } catch {
        error if @async.is_cancellation_error(error) => true
        error => raise error
      }
      assert_true(canceled_cleanly)
    }
    let recovered = (handle.capture_retained)(latest.id)
    assert_eq(recovered.pixels, latest.pixels)
    (handle.apply)(@ui.Action::Resize(800, 480))
    while (handle.inspect)().width != 800 || (handle.inspect)().height != 480 {
      @async.sleep(1)
    }
    let resized = (handle.capture_retained)((handle.retained_frame_id)())
    assert_eq(resized.width, 800)
    assert_eq(resized.height, 480)
    assert_eq(resized.pixels.length(), 800 * 480 * 4)
    assert_true(resized.generation > latest.generation)
    assert_true(resized.id > latest.id)
    assert_eq(resized.display_scale, latest.display_scale)
    println("WINDOW_RETAINED_FRAME_OK")
  })
  println("WINDOW_CAPTURE_OBSERVATION_OK")
  (handle.apply)(@ui.Action::Close)
}
