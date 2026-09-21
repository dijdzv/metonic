///|
#borrow(info)
extern "C" fn query_minimum(
  hwnd : UInt64,
  message : UInt,
  wparam : UInt64,
  info : FixedArray[Int],
) -> Int64 = "SendMessageW"

///|
fn tracking_minimum(window : @windows.Window) -> (Int, Int) {
  let info : FixedArray[Int] = FixedArray::make(10, 0)
  ignore(query_minimum(window.native_window_handle(), 0x24U, 0UL, info))
  (info[6], info[7])
}

///|
fn verify_minimum_size() -> Unit raise Error {
  let event_loop = @windows.EventLoop::new()
  defer event_loop.drop()
  let attributes = @window_core.WindowAttributes::default().with_visible(false)
  let window = event_loop.create_window(
    attributes
    .with_inner_size(@dpi.PhysicalSize(100, 100).into_size())
    .with_min_inner_size(@dpi.PhysicalSize(320, 360).into_size()),
  )
  defer window.drop()
  assert_eq(window.inner_size(), @dpi.PhysicalSize(320, 360))
  assert_eq(window.min_inner_size(), Some(@dpi.PhysicalSize(320, 360)))
  let outer = window.outer_size()
  assert_eq(tracking_minimum(window), (outer.width, outer.height))
  ignore(window.request_inner_size(@dpi.PhysicalSize(200, 200).into_size()))
  assert_eq(window.inner_size(), @dpi.PhysicalSize(320, 360))
  ignore(window.request_inner_size(@dpi.PhysicalSize(640, 480).into_size()))
  assert_eq(window.inner_size(), @dpi.PhysicalSize(640, 480))
  window.set_min_surface_size(Some(@dpi.PhysicalSize(400, 500).into_size()))
  assert_eq(window.inner_size(), @dpi.PhysicalSize(640, 500))
  assert_eq(window.min_surface_size(), Some(@dpi.PhysicalSize(400, 500)))
  window.set_min_inner_size(Some(@dpi.PhysicalSize(-1, 100).into_size()))
  assert_eq(window.min_inner_size(), Some(@dpi.PhysicalSize(400, 500)))
  window.set_min_inner_size(Some(@dpi.LogicalSize(320.5, 360.5).into_size()))
  let scale = window.scale_factor()
  let minimum = window.min_inner_size().unwrap()
  assert_true(minimum.width.to_double() >= 320.5 * scale)
  assert_true(minimum.width.to_double() < 320.5 * scale + 1.0)
  assert_true(minimum.height.to_double() >= 360.5 * scale)
  window.set_min_inner_size(Some(@dpi.LogicalSize(1.0 / 0.0, 20.0).into_size()))
  assert_eq(window.min_inner_size(), Some(minimum))
  window.set_min_surface_size(None)
  assert_eq(window.min_surface_size(), None)
  ignore(window.request_inner_size(@dpi.PhysicalSize(200, 200).into_size()))
  assert_eq(window.inner_size(), @dpi.PhysicalSize(200, 200))
  let other = event_loop.create_window(
    @window_core.WindowAttributes::default().with_visible(false),
  )
  defer other.drop()
  assert_eq(other.min_inner_size(), None)
  let default_tracking = tracking_minimum(other)
  assert_eq(tracking_minimum(window), default_tracking)
  other.drop()
  other.set_min_inner_size(Some(@dpi.PhysicalSize(500, 500).into_size()))
  assert_eq(other.min_inner_size(), None)
  println("WINDOW_MINIMUM_SIZE_OK scale=" + scale.to_string())
}
