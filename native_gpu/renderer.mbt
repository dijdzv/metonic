///|
/// Persistent native GPU renderer. Per-frame resources are released after each
/// readback; the pipeline and uniform state live for the renderer lifetime.
pub struct Renderer {
  instance : @wgpu.Instance
  adapter : @wgpu.Adapter
  device : @wgpu.Device
  queue : @wgpu.Queue
  pool : @wgpu.AutoReleasePool
  uniform : @wgpu.Buffer
  bind_group : @wgpu.BindGroup
  pipeline : @wgpu.RenderPipeline
  adapter_name_value : String
  registry : Map[Int, ReadbackTicket]
  mut next_id : Int
  mut closed : Bool
}

///|
fn renderer_uniform_bytes(words : Array[UInt]) -> Bytes {
  Bytes::makei(32, i => {
    ((words[i / 4] >> (i % 4 * 8)) & 0xFFU).reinterpret_as_int().to_byte()
  })
}

///|
fn renderer_rectangle_shader() -> String {
  (
    #|struct Rect { rect: vec4<u32>, flags: vec4<u32> };
    #|@group(0) @binding(0) var<uniform> u: Rect;
    #|@vertex fn vs_main(@builtin(vertex_index) i: u32) -> @builtin(position) vec4<f32> {
    #|  var p = array<vec2<f32>, 3>(vec2<f32>(-1.0,-1.0), vec2<f32>(3.0,-1.0), vec2<f32>(-1.0,3.0));
    #|  return vec4<f32>(p[i], 0.0, 1.0);
    #|}
    #|@fragment fn fs_main(@builtin(position) p: vec4<f32>) -> @location(0) vec4<f32> {
    #|  let x = u32(p.x); let y = u32(p.y);
    #|  let inside = x >= u.rect.x && x < u.rect.x + u.rect.z && y >= u.rect.y && y < u.rect.y + u.rect.w;
    #|  if (!inside) { return vec4<f32>(0.02,0.08,0.15,1.0); }
    #|  if (u.flags.x == 1u) { return vec4<f32>(0.95,0.38,0.10,1.0); }
    #|  return vec4<f32>(0.08,0.65,0.68,1.0);
    #|}
  )
}

///|
priv suberror RendererError {
  RendererClosed
  RendererInvalidDimensions
  RendererInvalidRectangle
  RendererPendingReadback
  RendererPendingInitialization
}

///|
pub async fn Renderer::new(
  force_fallback : Bool,
  initialization : Initialization,
) -> Renderer raise Error {
  if initialization.pending_count() != 0 {
    raise RendererPendingInitialization
  }
  let instance = @wgpu.Instance::create()
  errdefer instance.release()
  let adapter = initialize_adapter(initialization, instance, force_fallback)
  errdefer adapter.release()
  let device = initialize_device(initialization, instance, adapter)
  let queue = device.queue()
  let pool = @wgpu.AutoReleasePool::new()
  let layout = pool.track_bind_group_layout(
    device.create_bind_group_layout_uniform_buffer(),
  )
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
  let pipeline_layout = pool.track_pipeline_layout(
    device.create_pipeline_layout_1(layout),
  )
  let shader = pool.track_shader_module(
    device.create_shader_module_wgsl(renderer_rectangle_shader()),
  )
  let pipeline = pool.track_render_pipeline(
    device.create_render_pipeline_rgba8_with_layout(pipeline_layout, shader),
  )
  {
    instance,
    adapter,
    device,
    queue,
    pool,
    uniform,
    bind_group,
    pipeline,
    adapter_name_value: adapter.info_device(),
    registry: Map([]),
    next_id: 0,
    closed: false,
  }
}

///|
pub async fn Renderer::render(
  self : Renderer,
  width : Int,
  height : Int,
  x : Int,
  y : Int,
  rw : Int,
  rh : Int,
  active : Int,
) -> Bytes raise Error {
  if self.closed {
    raise RendererClosed
  }
  if !self.registry.is_empty() {
    raise RendererPendingReadback
  }
  if width < 1 || width > 2048 || height < 1 || height > 2048 {
    raise RendererInvalidDimensions
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
    raise RendererInvalidRectangle
  }
  let width_u = width.reinterpret_as_uint()
  let height_u = height.reinterpret_as_uint()
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
  let texture = self.device.create_texture_rgba8_2d(width_u, height_u)
  defer texture.release()
  let view = texture.create_view()
  defer view.release()
  let encoder = self.device.create_command_encoder()
  defer encoder.release()
  let pass = encoder.begin_render_pass_color(view)
  pass.set_pipeline(self.pipeline)
  pass.set_bind_group(0U, self.bind_group, [])
  pass.draw(3U, 1U, 0U, 0U)
  pass.end()
  defer pass.release()
  let row = (width_u * 4U + 255U) / 256U * 256U
  let padded_size = row * height_u
  let readback = self.device.create_buffer(
    size=padded_size.to_uint64(),
    usage=@wgpu.BufferUsage::from_u64(
      @wgpu.BUFFER_USAGE_MAP_READ | @wgpu.BUFFER_USAGE_COPY_DST,
    ),
  )
  defer readback.release()
  encoder.copy_texture_to_buffer_rgba8(texture, readback, width_u, height_u)
  let command = encoder.finish()
  defer command.release()
  let id = self.next_id
  self.next_id += 1
  let padded = read_gpu_buffer(
    self.instance,
    self.device,
    self.queue,
    command,
    readback,
    0UL,
    padded_size.to_uint64(),
    self.registry,
    id,
  )
  Bytes::makei(width * height * 4, i => {
    let pixel = i / 4
    let channel = i % 4
    let px = pixel % width
    let py = pixel / width
    padded[(py.reinterpret_as_uint() * row + px.reinterpret_as_uint() * 4U).reinterpret_as_int() +
    channel]
  })
}

///|
pub fn Renderer::close(self : Renderer) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  self.pool.release()
  self.queue.release()
  self.device.release()
  self.adapter.release()
  self.instance.release()
}

///|
pub fn Renderer::is_poisoned(self : Renderer) -> Bool {
  self.closed || !self.registry.is_empty()
}

///|
pub fn Renderer::adapter_name(self : Renderer) -> String {
  self.adapter_name_value
}
