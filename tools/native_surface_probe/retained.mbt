///|
fn retained_frame_probe(
  instance : @wgpu.Instance,
  surface : @wgpu.Surface,
  adapter : @wgpu.Adapter,
  device : @wgpu.Device,
  queue : @wgpu.Queue,
) -> Unit raise Error {
  let usage = @wgpu.TEXTURE_USAGE_RENDER_ATTACHMENT |
    @wgpu.TEXTURE_USAGE_COPY_SRC
  assert_eq(surface.capabilities_usages_u64(adapter).to_u64() & usage, usage)
  let format = surface.configure_default(
    adapter,
    device,
    64U,
    32U,
    @wgpu.TextureUsage::from_u64(usage),
  )
  assert_true(format.to_u32() != 0U)
  let retained = device.create_texture_u32(
    64U,
    32U,
    1U,
    @wgpu.TextureUsage::from_u64(
      @wgpu.TEXTURE_USAGE_COPY_SRC | @wgpu.TEXTURE_USAGE_COPY_DST,
    ),
    @wgpu.TextureDimension::from_u32(@wgpu.TEXTURE_DIMENSION_2D),
    format,
  )
  defer retained.release()
  for index in 0..<2 {
    let frame = surface.get_current_frame_or_raise()
    defer frame.release()
    let view = frame.texture.create_view()
    defer view.release()
    let encoder = device.create_command_encoder()
    defer encoder.release()
    let pass = encoder.begin_render_pass_color_clear(
      view,
      if index == 0 {
        1.0
      } else {
        0.0
      },
      0.0,
      if index == 0 {
        0.0
      } else {
        1.0
      },
      1.0,
    )
    pass.end()
    pass.release()
    if index == 0 {
      encoder.copy_texture_to_texture_rgba8(frame.texture, retained, 64U, 32U)
    }
    let command = encoder.finish()
    defer command.release()
    queue.submit_one(command)
    frame.present_or_raise()
  }
  assert_eq(
    surface
    .configure_default(
      adapter,
      device,
      128U,
      64U,
      @wgpu.TextureUsage::from_u64(usage),
    )
    .to_u32(),
    format.to_u32(),
  )
  surface.unconfigure()
  let buffer = device.create_buffer(
    size=8192UL,
    usage=@wgpu.BufferUsage::from_u64(
      @wgpu.BUFFER_USAGE_MAP_READ | @wgpu.BUFFER_USAGE_COPY_DST,
    ),
  )
  defer buffer.release()
  let encoder = device.create_command_encoder()
  defer encoder.release()
  encoder.copy_texture_to_buffer_rgba8(retained, buffer, 64U, 32U)
  let command = encoder.finish()
  defer command.release()
  queue.submit_one(command)
  let pixels = buffer.map_read_sync_or_raise(instance, 0UL, 8192UL)
  let bgra = format.to_u32() == @wgpu.TEXTURE_FORMAT_BGRA8_UNORM ||
    format.to_u32() == @wgpu.TEXTURE_FORMAT_BGRA8_UNORM_SRGB
  assert_eq(pixels.length(), 8192)
  for pixel in 0..<2048 {
    let offset = pixel * 4
    assert_eq(pixels[offset + (if bgra { 2 } else { 0 })], b'\xff')
    assert_eq(pixels[offset + 1], b'\x00')
    assert_eq(pixels[offset + (if bgra { 0 } else { 2 })], b'\x00')
    assert_eq(pixels[offset + 3], b'\xff')
  }
  println("RETAINED_SURFACE_PIXELS_OK red_after_blue_resize_unconfigure")
}
