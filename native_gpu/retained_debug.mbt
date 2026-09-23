///|
priv struct RetainedImage {
  mut present_id : UInt?
  mut statistics_epoch : Int64
  mut display_confirmed : Bool
  texture : @wgpu.Texture
  width : UInt
  height : UInt
  format : @wgpu.TextureFormat
  generation : Int64
  display_scale : Double?
}

///|
struct FrameRetention {
  mut feedback : ((@wgpu.Surface) -> DisplayObservation)?
  mut epoch : Int64
  mut last_present : UInt?
  supported : Bool
  mut enabled : Bool
  mut generation : Int64
  mut sequence : Int64
  mut images : Array[(Int64, RetainedImage)]
}

///|
fn FrameRetention::resource_footprint(self : FrameRetention) -> (Int, UInt64) {
  let mut bytes = 0UL
  for pair in self.images {
    bytes += pair.1.width.to_uint64() * pair.1.height.to_uint64() * 4UL
  }
  (self.images.length(), bytes)
}

///|
priv struct PendingFrame {
  mut image : RetainedImage?
}

///|
pub(all) suberror RetainedFrameError {
  RetentionUnavailable
  InvalidFrame
  FrameNotSubmitted
  FrameEvicted
}

///|
fn FrameRetention::new(
  surface : @wgpu.Surface,
  adapter : @wgpu.Adapter,
) -> FrameRetention {
  {
    feedback: None,
    epoch: 1L,
    last_present: None,
    supported: (
      surface.capabilities_usages_u64(adapter).to_u64() &
      @wgpu.TEXTURE_USAGE_COPY_SRC
    ) !=
    0UL,
    enabled: false,
    generation: 1L,
    sequence: 0L,
    images: [],
  }
}

///|
fn FrameRetention::usage(self : FrameRetention) -> @wgpu.TextureUsage {
  @wgpu.TextureUsage::from_u64(
    @wgpu.TEXTURE_USAGE_RENDER_ATTACHMENT |
    (if self.supported { @wgpu.TEXTURE_USAGE_COPY_SRC } else { 0UL }),
  )
}

///|
pub fn SurfaceRenderer::enable_frame_retention(self : SurfaceRenderer) -> Bool {
  self.retention.enabled = !self.closed &&
    !self.poisoned &&
    self.retention.supported &&
    self.retention.sequence < 9223372036854775807L &&
    self.retention.generation < 9223372036854775807L
  self.retention.enabled
}

///|
pub fn SurfaceRenderer::retained_frame_id(self : SurfaceRenderer) -> Int64 {
  self.retention.sequence
}

///|
fn FrameRetention::reconfigured(self : FrameRetention) -> Unit {
  self.invalidate_display()
  if self.generation == 9223372036854775807L {
    self.close()
  } else {
    self.generation += 1L
  }
}

///|
fn FrameRetention::copy(
  self : FrameRetention,
  device : @wgpu.Device,
  encoder : @wgpu.CommandEncoder,
  texture : @wgpu.Texture,
  width : UInt,
  height : UInt,
  format : @wgpu.TextureFormat,
  display_scale : Double?,
) -> PendingFrame {
  if !self.enabled ||
    self.sequence == 9223372036854775807L ||
    self.generation == 9223372036854775807L {
    return { image: None, }
  }
  let target = device.create_texture_u32(
    width,
    height,
    1U,
    @wgpu.TextureUsage::from_u64(
      @wgpu.TEXTURE_USAGE_COPY_SRC | @wgpu.TEXTURE_USAGE_COPY_DST,
    ),
    @wgpu.TextureDimension::from_u32(@wgpu.TEXTURE_DIMENSION_2D),
    format,
  )
  encoder.copy_texture_to_texture_rgba8(texture, target, width, height)
  {
    image: Some({
      present_id: None,
      statistics_epoch: 0L,
      display_confirmed: false,
      texture: target,
      width,
      height,
      format,
      generation: self.generation,
      display_scale,
    }),
  }
}

///|
fn PendingFrame::close(self : PendingFrame) -> Unit {
  if self.image is Some(image) {
    image.texture.release()
    self.image = None
  }
}

///|
fn FrameRetention::publish(
  self : FrameRetention,
  pending : PendingFrame,
  attempt : PresentationAttempt,
  surface : @wgpu.Surface,
) -> Unit {
  let presented = self.observe_display(surface)
  if pending.image is Some(image) {
    if presented is Some(last) &&
      attempt.before is Some(before) &&
      attempt.epoch == self.epoch &&
      last > before {
      image.present_id = Some(last)
      image.statistics_epoch = self.epoch
    }
    pending.image = None
    self.sequence += 1L
    if self.images.length() == 2 {
      self.images[0].1.texture.release()
      self.images = [self.images[1]]
    }
    self.images.push((self.sequence, image))
  }
}

///|
fn FrameRetention::close(self : FrameRetention) -> Unit {
  self.feedback = None
  for pair in self.images {
    pair.1.texture.release()
  }
  self.images = []
  self.enabled = false
}

///|
pub struct RetainedCapture {
  display_confirmed : Bool
  id : Int64
  generation : Int64
  width : Int
  height : Int
  pixels : Bytes
  display_scale : Double?
}

///|
pub async fn SurfaceRenderer::capture_retained(
  self : SurfaceRenderer,
  id : Int64,
) -> RetainedCapture {
  if self.closed {
    raise SurfaceRendererClosed
  }
  if self.poisoned {
    raise SurfaceRendererInvalidConfiguration
  }
  if !self.readbacks.is_empty() {
    raise RendererPendingReadback
  }
  if !self.retention.enabled {
    raise RetentionUnavailable
  }
  if id <= 0L {
    raise RetainedFrameError::InvalidFrame
  }
  if id > self.retention.sequence {
    raise FrameNotSubmitted
  }
  let mut image : RetainedImage? = None
  for pair in self.retention.images {
    if pair.0 == id {
      image = Some(pair.1)
      break
    }
  }
  guard image is Some(image) else { raise FrameEvicted }
  let texture = image.texture.add_ref()
  defer texture.release()
  let row = (image.width * 4U + 255U) / 256U * 256U
  let size = row * image.height
  let buffer = self.device.create_buffer(
    size=size.to_uint64(),
    usage=@wgpu.BufferUsage::from_u64(
      @wgpu.BUFFER_USAGE_MAP_READ | @wgpu.BUFFER_USAGE_COPY_DST,
    ),
  )
  defer buffer.release()
  let encoder = self.device.create_command_encoder()
  defer encoder.release()
  encoder.copy_texture_to_buffer_rgba8(
    texture,
    buffer,
    image.width,
    image.height,
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
  let width = image.width.reinterpret_as_int()
  let height = image.height.reinterpret_as_int()
  let bgra = image.format.to_u32() == @wgpu.TEXTURE_FORMAT_BGRA8_UNORM ||
    image.format.to_u32() == @wgpu.TEXTURE_FORMAT_BGRA8_UNORM_SRGB
  let pixels = Bytes::makei(width * height * 4, i => {
    let source = if bgra && i % 4 == 0 {
      i + 2
    } else if bgra && i % 4 == 2 {
      i - 2
    } else {
      i
    }
    padded[source / (width * 4) * row.reinterpret_as_int() +
    source % (width * 4)]
  })
  {
    display_confirmed: image.display_confirmed,
    id,
    generation: image.generation,
    width,
    height,
    pixels,
    display_scale: image.display_scale,
  }
}
