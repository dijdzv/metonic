///|
async fn capture_observation(handle : @ui.Handle) -> Unit {
  @async.with_timeout(10000, () => {
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
