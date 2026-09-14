///|
fn prepare_display_probe(renderer : @gpu.SurfaceRenderer) -> Unit raise Error {
  assert_true(renderer.enable_frame_retention())
  let count = Ref(0U)
  renderer.set_display_feedback(fn(_) {
    count.val += 1U
    @gpu.DisplayObservation::Sample(count.val, 0U, 0L, 0U, 0U)
  })
}

///|
async fn verify_pending_display(renderer : @gpu.SurfaceRenderer) -> Unit {
  let frame = renderer.retained_frame_id()
  assert_eq(frame, 1L)
  assert_true(
    renderer.poll_display_status(frame) is @gpu.DisplayStatus::Pending,
  )
  let capture = renderer.capture_retained(frame)
  assert_eq(capture.id, frame)
  assert_false(capture.display_confirmed)
}

///|
async fn verify_closed_display(renderer : @gpu.SurfaceRenderer) -> Unit {
  let frame = renderer.retained_frame_id()
  assert_true(renderer.poll_display_status(frame) is @gpu.DisplayStatus::Closed)
  let rejected = try {
    ignore(renderer.capture_retained(frame))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  println("SURFACE_RETAINED_GENERATION_CLOSED")
}
