///|
pub struct SurfaceRenderer {
  instance : @wgpu.Instance
  surface : @wgpu.Surface
  adapter : @wgpu.Adapter
  device : @wgpu.Device
  queue : @wgpu.Queue
  pool : @wgpu.AutoReleasePool
  uniform : @wgpu.Buffer
  bind_group : @wgpu.BindGroup
  pipeline : @wgpu.RenderPipeline
  adapter_name_value : String
  mut width : UInt
  mut height : UInt
  format : @wgpu.TextureFormat
  mut closed : Bool
  mut poisoned : Bool
  mut text_layers : Array[SurfaceText]
  readbacks : Map[Int, ReadbackTicket]
}

///|
priv suberror SurfaceRendererError {
  SurfaceRendererClosed
  SurfaceRendererInvalidDimensions
  SurfaceRendererInvalidRectangle
  SurfaceRendererInvalidConfiguration
  SurfaceRendererAcquire(UInt)
}

///|
pub async fn SurfaceRenderer::new(
  instance : @wgpu.Instance,
  surface : @wgpu.Surface,
  force_fallback : Bool,
  initialization : Initialization,
) -> SurfaceRenderer raise Error {
  if initialization.pending_count() != 0 {
    raise RendererPendingInitialization
  }
  let kept_instance = instance.add_ref()
  errdefer kept_instance.release()
  let kept_surface = surface.add_ref()
  errdefer kept_surface.release()
  // WhyNot: SurfaceRenderer does not own the HWND behind this surface;
  // callers must keep the window alive until close and pending_count() == 0.
  // WhyNot: each renderer generation needs a fresh surface because a DX12
  // swap chain may remain attached when a surface is reused with a new device.
  let adapter = initialize_adapter(
    initialization,
    kept_instance,
    force_fallback,
    compatible_surface=Some(kept_surface),
    power_preference=@wgpu.POWER_PREFERENCE_HIGH_PERFORMANCE,
  )
  errdefer adapter.release()
  let device = initialize_device(initialization, kept_instance, adapter)
  errdefer device.release()
  let queue = device.queue()
  errdefer queue.release()
  let format = kept_surface.configure_default(
    adapter,
    device,
    640U,
    360U,
    @wgpu.TextureUsage::from_u64(@wgpu.TEXTURE_USAGE_RENDER_ATTACHMENT),
  )
  if format.to_u32() == 0U {
    kept_surface.unconfigure()
    raise SurfaceRendererInvalidConfiguration
  }
  let pool = @wgpu.AutoReleasePool::new()
  let shader = pool.track_shader_module(
    device.create_shader_module_wgsl(renderer_rectangle_shader()),
  )
  let pipeline = pool.track_render_pipeline(
    device.create_render_pipeline_color_format(shader, format),
  )
  let layout = pool.track_bind_group_layout(pipeline.get_bind_group_layout(0U))
  let uniform = pool.track_buffer(
    device.create_buffer(
      size=32UL,
      usage=@wgpu.BufferUsage::from_u64(
        @wgpu.BUFFER_USAGE_UNIFORM | @wgpu.BUFFER_USAGE_COPY_DST,
      ),
    ),
  )
  let bind_group = pool.track_bind_group(
    device.create_bind_group_uniform_buffer(layout, uniform),
  )
  {
    instance: kept_instance,
    surface: kept_surface,
    adapter,
    device,
    queue,
    pool,
    uniform,
    bind_group,
    pipeline,
    adapter_name_value: adapter.info_device(),
    width: 640U,
    height: 360U,
    format,
    closed: false,
    poisoned: false,
    text_layers: [],
    readbacks: Map([]),
  }
}

///|
fn SurfaceRenderer::configure(
  self : SurfaceRenderer,
  width : UInt,
  height : UInt,
) -> Unit raise Error {
  let format = self.surface.configure_default(
    self.adapter,
    self.device,
    width,
    height,
    @wgpu.TextureUsage::from_u64(@wgpu.TEXTURE_USAGE_RENDER_ATTACHMENT),
  )
  if format.to_u32() == 0U || format != self.format {
    self.poisoned = true
    raise SurfaceRendererInvalidConfiguration
  }
  self.width = width
  self.height = height
}

///|
fn[T] acquire_surface_texture(
  acquire : () -> T,
  status : (T) -> UInt,
  release : (T) -> Unit,
  reconfigure : () -> Unit raise Error,
) -> T raise Error {
  let first = acquire()
  let first_status = status(first)
  if first_status == @wgpu.SURFACE_GET_CURRENT_TEXTURE_STATUS_SUCCESS_OPTIMAL ||
    first_status == @wgpu.SURFACE_GET_CURRENT_TEXTURE_STATUS_SUCCESS_SUBOPTIMAL {
    return first
  }
  release(first)
  if first_status != @wgpu.SURFACE_GET_CURRENT_TEXTURE_STATUS_OUTDATED &&
    first_status != @wgpu.SURFACE_GET_CURRENT_TEXTURE_STATUS_LOST {
    raise SurfaceRendererAcquire(first_status)
  }
  reconfigure()
  let second = acquire()
  let second_status = status(second)
  if second_status == @wgpu.SURFACE_GET_CURRENT_TEXTURE_STATUS_SUCCESS_OPTIMAL ||
    second_status == @wgpu.SURFACE_GET_CURRENT_TEXTURE_STATUS_SUCCESS_SUBOPTIMAL {
    second
  } else {
    release(second)
    raise SurfaceRendererAcquire(second_status)
  }
}

///|
pub fn SurfaceRenderer::present(
  self : SurfaceRenderer,
  width : Int,
  height : Int,
  x : Int,
  y : Int,
  rw : Int,
  rh : Int,
  active : Int,
) -> Unit raise Error {
  if self.closed {
    raise SurfaceRendererClosed
  }
  if self.poisoned {
    raise SurfaceRendererInvalidConfiguration
  }
  if width < 1 || width > 2048 || height < 1 || height > 2048 {
    raise SurfaceRendererInvalidDimensions
  }
  if x < 0 ||
    y < 0 ||
    rw < 1 ||
    rh < 1 ||
    x >= width ||
    y >= height ||
    rw > width - x ||
    rh > height - y ||
    (active != 0 && active != 1) {
    raise SurfaceRendererInvalidRectangle
  }
  let width_u = width.reinterpret_as_uint()
  let height_u = height.reinterpret_as_uint()
  if width_u != self.width || height_u != self.height {
    self.configure(width_u, height_u)
  }
  let surface_texture = acquire_surface_texture(
    () => self.surface.get_current_texture(),
    st => st.status(),
    st => st.release(),
    () => self.configure(width_u, height_u),
  )
  let texture = surface_texture.take_texture()
  surface_texture.release()
  defer texture.release()
  let view = texture.create_view()
  defer view.release()
  self.queue.write_buffer(
    self.uniform,
    0UL,
    renderer_uniform_bytes([
      x.reinterpret_as_uint(),
      y.reinterpret_as_uint(),
      rw.reinterpret_as_uint(),
      rh.reinterpret_as_uint(),
      active.reinterpret_as_uint(),
      0U,
      0U,
      0U,
    ]),
  )
  let encoder = self.device.create_command_encoder()
  defer encoder.release()
  let pass = encoder.begin_render_pass_color(view)
  self.draw_pass(pass)
  let command = encoder.finish()
  defer command.release()
  self.queue.submit_one(command)
  self.surface.present_or_raise()
}

///|
fn SurfaceRenderer::draw_pass(
  self : SurfaceRenderer,
  pass : @wgpu.RenderPass,
) -> Unit {
  pass.set_pipeline(self.pipeline)
  pass.set_bind_group(0U, self.bind_group, [])
  pass.draw(3U, 1U, 0U, 0U)
  for text in self.text_layers {
    pass.set_pipeline(text.pipeline)
    pass.set_bind_group(0U, text.bind_group, [])
    pass.draw(3U, 1U, 0U, 0U)
  }
  pass.end()
  pass.release()
}

///|
pub fn SurfaceRenderer::close(self : SurfaceRenderer) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  for text in self.text_layers {
    text.pool.release()
  }
  self.text_layers = []
  self.surface.unconfigure()
  self.pool.release()
  self.queue.release()
  self.device.release()
  self.adapter.release()
  self.surface.release()
  self.instance.release()
}

///|
pub fn SurfaceRenderer::adapter_name(self : SurfaceRenderer) -> String {
  self.adapter_name_value
}
