///|
pub async fn SurfaceRenderer::capture_frame(
  self : SurfaceRenderer,
) -> Bytes raise Error {
  if self.closed {
    raise SurfaceRendererClosed
  }
  if self.poisoned {
    raise SurfaceRendererInvalidConfiguration
  }
  if !self.readbacks.is_empty() {
    raise RendererPendingReadback
  }
  let frame_width = self.width
  let frame_height = self.height
  let texture = self.device.create_texture_u32(
    frame_width,
    frame_height,
    1U,
    @wgpu.TextureUsage::from_u64(
      @wgpu.TEXTURE_USAGE_RENDER_ATTACHMENT | @wgpu.TEXTURE_USAGE_COPY_SRC,
    ),
    @wgpu.TextureDimension::from_u32(@wgpu.TEXTURE_DIMENSION_2D),
    self.format,
  )
  defer texture.release()
  let view = texture.create_view()
  defer view.release()
  let encoder = self.device.create_command_encoder()
  defer encoder.release()
  self.draw_pass(encoder.begin_render_pass_color(view))
  let row = (frame_width * 4U + 255U) / 256U * 256U
  let size = row * frame_height
  let buffer = self.device.create_buffer(
    size=size.to_uint64(),
    usage=@wgpu.BufferUsage::from_u64(
      @wgpu.BUFFER_USAGE_MAP_READ | @wgpu.BUFFER_USAGE_COPY_DST,
    ),
  )
  defer buffer.release()
  encoder.copy_texture_to_buffer_rgba8(
    texture, buffer, frame_width, frame_height,
  )
  let command = encoder.finish()
  defer command.release()
  let padded = read_gpu_buffer(
    self.instance,
    self.device,
    self.queue,
    command,
    buffer,
    0UL,
    size.to_uint64(),
    self.readbacks,
    0,
  )
  let width = frame_width.reinterpret_as_int()
  Bytes::makei(width * frame_height.reinterpret_as_int() * 4, i => {
    padded[i / (width * 4) * row.reinterpret_as_int() + i % (width * 4)]
  })
}
