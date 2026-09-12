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
  })
  println("WINDOW_CAPTURE_OBSERVATION_OK")
  (handle.apply)(@ui.Action::Close)
}
