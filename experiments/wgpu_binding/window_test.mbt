///|
extern "C" fn metonic_binding_hinstance() -> @c.OpaquePtr = "metonic_binding_hinstance"

///|
extern "C" fn metonic_binding_hwnd() -> @c.OpaquePtr = "metonic_binding_hwnd"

///|
extern "C" fn metonic_window_create() -> Int = "metonic_window_create"

///|
extern "C" fn metonic_window_next_event() -> Int = "metonic_window_next_event"

///|
extern "C" fn metonic_window_event_x() -> Int = "metonic_window_event_x"

///|
extern "C" fn metonic_window_event_y() -> Int = "metonic_window_event_y"

///|
extern "C" fn metonic_window_test_mode() -> Int = "metonic_window_test_mode"

///|
extern "C" fn metonic_window_test_step(step : Int, x : Int, y : Int) -> Int = "metonic_window_test_step"

///|
extern "C" fn metonic_window_destroy() -> Unit = "metonic_window_destroy"

///|
fn bytes32(words : Array[UInt]) -> Bytes {
  Bytes::makei(32, i => {
    ((words[i / 4] >> (i % 4 * 8)) & 0xFFU).reinterpret_as_int().to_byte()
  })
}

///|
test "native window surface rectangle" {
  assert_eq(@env.get_env_var("METONIC_WINDOW_TEST"), Some("1"))
  assert_eq(metonic_window_create(), 0)
  defer metonic_window_destroy()
  assert_eq(metonic_window_test_mode(), 1)
  let instance = @wgpu.Instance::create()
  defer instance.release()
  let adapter = instance.request_adapter_sync_options_u32(
    backend_type_u32=@wgpu.BACKEND_TYPE_D3_D12,
    force_fallback_adapter=@env.get_env_var("METONIC_GPU_FALLBACK") == Some("1"),
  )
  defer adapter.release()
  assert_eq(adapter.info_backend_type_u32(), @wgpu.BACKEND_TYPE_D3_D12)
  let device = adapter.request_device_sync(instance)
  defer device.release()
  let queue = device.queue()
  defer queue.release()
  let surface = instance.create_surface_windows_hwnd(
    metonic_binding_hinstance(),
    metonic_binding_hwnd(),
  )
  defer surface.release()
  let format = surface.configure_default(
    adapter,
    device,
    640U,
    360U,
    @wgpu.TextureUsage::from_u64(@wgpu.TEXTURE_USAGE_RENDER_ATTACHMENT),
  )
  defer surface.unconfigure()
  let shader = device.create_shader_module_wgsl(rectangle_shader())
  defer shader.release()
  let pipeline = device.create_render_pipeline_color_format(shader, format)
  defer pipeline.release()
  let layout = pipeline.get_bind_group_layout(0U)
  defer layout.release()
  let uniform = device.create_buffer(
    size=32UL,
    usage=@wgpu.BufferUsage::from_u64(
      @wgpu.BUFFER_USAGE_UNIFORM | @wgpu.BUFFER_USAGE_COPY_DST,
    ),
  )
  defer uniform.release()
  let bind_group = device.create_bind_group_uniform_buffer(layout, uniform)
  defer bind_group.release()
  let mut width = 640U
  let mut height = 360U
  let mut x = 260U
  let mut y = 144U
  let mut active = 0U
  let mut stage = 0
  let mut frames = 0
  let mut closed = false
  fn render() -> Unit raise {
    queue.write_buffer(
      uniform,
      0UL,
      bytes32([x, y, 120U, 72U, active, 0U, 0U, 0U]),
    )
    let frame = surface.get_current_frame_or_raise()
    defer frame.release()
    let view = frame.texture.create_view()
    defer view.release()
    let encoder = device.create_command_encoder()
    defer encoder.release()
    let pass = encoder.begin_render_pass_color(view)
    defer pass.release()
    pass.set_pipeline(pipeline)
    pass.set_bind_group(0U, bind_group, [])
    pass.draw(3U, 1U, 0U, 0U)
    pass.end()
    let command = encoder.finish()
    defer command.release()
    queue.submit_one(command)
    frame.present_or_raise()
    frames += 1
  }
  render()
  assert_eq(metonic_window_test_step(0, 0, 0), 0)
  let mut count = 0
  while !closed && count < 64 {
    let event = metonic_window_next_event()
    count += 1
    if event == 5 {
      assert_eq(stage, 3)
      stage = 4
      closed = true
    } else if event == 1 {
      render()
    } else if event == 2 {
      width = metonic_window_event_x().reinterpret_as_uint()
      height = metonic_window_event_y().reinterpret_as_uint()
      assert_eq(width >= 120U, true)
      assert_eq(height >= 72U, true)
      x = x.min(width - 120U)
      y = y.min(height - 72U)
      let next_format = surface.configure_default(
        adapter,
        device,
        width,
        height,
        @wgpu.TextureUsage::from_u64(@wgpu.TEXTURE_USAGE_RENDER_ATTACHMENT),
      )
      assert_eq(next_format.raw, format.raw)
      render()
      if stage == 1 && width == 317U && height == 193U {
        assert_eq(x, 197U)
        assert_eq(y, 121U)
        stage = 2
        assert_eq(
          metonic_window_test_step(
            2,
            (x + 1U).reinterpret_as_int(),
            (y + 1U).reinterpret_as_int(),
          ),
          0,
        )
      }
    } else if event == 3 && metonic_window_event_x() == 39 {
      assert_eq(stage, 0)
      x += 10U
      assert_eq(x, 270U)
      stage = 1
      assert_eq(metonic_window_test_step(1, 0, 0), 0)
      render()
    } else if event == 4 {
      assert_eq(stage, 2)
      let px = metonic_window_event_x().reinterpret_as_uint()
      let py = metonic_window_event_y().reinterpret_as_uint()
      assert_eq(px >= x && px < x + 120U && py >= y && py < y + 72U, true)
      active = 1U
      stage = 3
      assert_eq(metonic_window_test_step(3, 0, 0), 0)
      render()
    } else {
      assert_eq(false, true)
    }
  }
  assert_eq(closed, true)
  assert_eq(stage, 4)
  assert_eq(active, 1U)
  assert_eq(frames >= 3, true)
  println(
    "WINDOW_SURFACE_OK adapter=" +
    adapter.info_device() +
    " frames=" +
    frames.to_string(),
  )
}
