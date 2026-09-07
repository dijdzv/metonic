///|
pub struct SurfaceText {
  pool : @wgpu.AutoReleasePool
  pipeline : @wgpu.RenderPipeline
  bind_group : @wgpu.BindGroup
}

///|
priv suberror SurfaceTextError {
  InvalidTextPixels
} derive(Debug)

///|
fn surface_text_shader() -> String {
  let source =
    #|@group(0) @binding(0) var glyphs : texture_2d<f32>;
    #|@vertex fn vs_main(@builtin(vertex_index) i : u32) -> @builtin(position) vec4f {
    #|  let p = array<vec2f, 3>(vec2f(-1.0, -1.0), vec2f(3.0, -1.0), vec2f(-1.0, 3.0));
    #|  return vec4f(p[i], 0.0, 1.0);
    #|}
    #|@fragment fn fs_main(@builtin(position) p : vec4f) -> @location(0) vec4f {
    #|  let at = vec2<i32>(p.xy) - vec2<i32>(8, 8);
    #|  let size = vec2<i32>(textureDimensions(glyphs));
    #|  if (any(at < vec2<i32>(0)) || any(at >= size)) { discard; }
    #|  return textureLoad(glyphs, at, 0);
    #|}
  source
}

///|
pub fn SurfaceRenderer::set_text_pixels(
  self : SurfaceRenderer,
  width : Int,
  height : Int,
  pixels : Bytes,
) -> Unit raise Error {
  if self.closed {
    raise SurfaceRendererClosed
  }
  if width < 1 ||
    width > 1024 ||
    height < 1 ||
    height > 128 ||
    pixels.length() != width * height * 4 {
    raise InvalidTextPixels
  }
  let pool = @wgpu.AutoReleasePool::new()
  let texture = pool.track_texture(
    self.device.create_texture_rgba8_2d_with_usage(
      width.reinterpret_as_uint(),
      height.reinterpret_as_uint(),
      @wgpu.TextureUsage::from_u64(
        @wgpu.TEXTURE_USAGE_TEXTURE_BINDING | @wgpu.TEXTURE_USAGE_COPY_DST,
      ),
    ),
  )
  self.queue.write_texture_rgba8_2d(
    texture,
    width.reinterpret_as_uint(),
    height.reinterpret_as_uint(),
    pixels,
  )
  let view = pool.track_texture_view(texture.create_view())
  let shader = pool.track_shader_module(
    self.device.create_shader_module_wgsl(surface_text_shader()),
  )
  let pipeline = pool.track_render_pipeline(
    self.device.create_render_pipeline_color_format(shader, self.format),
  )
  let layout = pool.track_bind_group_layout(pipeline.get_bind_group_layout(0U))
  let bind_group = pool.track_bind_group(
    self.device.create_bind_group_texture_2d(layout, view),
  )
  let next : SurfaceText = { pool, pipeline, bind_group, }
  match self.text_layer {
    Some(old) => old.pool.release()
    None => ()
  }
  self.text_layer = Some(next)
}
