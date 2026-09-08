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
fn surface_text_shader(x : Int, y : Int) -> String {
  let source =
    #|@group(0) @binding(0) var glyphs : texture_2d<f32>;
    #|@vertex fn vs_main(@builtin(vertex_index) i : u32) -> @builtin(position) vec4f {
    #|  let p = array<vec2f, 3>(vec2f(-1.0, -1.0), vec2f(3.0, -1.0), vec2f(-1.0, 3.0));
    #|  return vec4f(p[i], 0.0, 1.0);
    #|}
    #|@fragment fn fs_main(@builtin(position) p : vec4f) -> @location(0) vec4f {
    #|  let at = vec2<i32>(p.xy) - vec2<i32>(ORIGIN_X, ORIGIN_Y);
    #|  let size = vec2<i32>(textureDimensions(glyphs));
    #|  if (any(at < vec2<i32>(0)) || any(at >= size)) { discard; }
    #|  return textureLoad(glyphs, at, 0);
    #|}
  source
  .replace_all(old="ORIGIN_X", new=x.to_string())
  .replace_all(old="ORIGIN_Y", new=y.to_string())
}

///|
pub(all) struct TextLayer {
  x : Int
  y : Int
  width : Int
  height : Int
  pixels : Bytes
}

///|
pub fn SurfaceRenderer::set_text_pixels(
  self : SurfaceRenderer,
  width : Int,
  height : Int,
  pixels : Bytes,
) -> Unit raise Error {
  self.set_text_layers([{ x: 8, y: 8, width, height, pixels, }])
}

///|
pub fn SurfaceRenderer::set_text_layers(
  self : SurfaceRenderer,
  layers : Array[TextLayer],
) -> Unit raise Error {
  if self.closed {
    raise SurfaceRendererClosed
  }
  if layers.length() > 16 {
    raise InvalidTextPixels
  }
  for layer in layers {
    if layer.x < 0 ||
      layer.y < 0 ||
      layer.x > 2048 ||
      layer.y > 2048 ||
      layer.width < 1 ||
      layer.width > 1024 ||
      layer.height < 1 ||
      layer.height > 128 ||
      layer.pixels.length() != layer.width * layer.height * 4 {
      raise InvalidTextPixels
    }
  }
  let next = layers.map(layer => self.make_text_layer(layer))
  for old in self.text_layers {
    old.pool.release()
  }
  self.text_layers = next
}

///|
fn SurfaceRenderer::make_text_layer(
  self : SurfaceRenderer,
  layer : TextLayer,
) -> SurfaceText {
  let pool = @wgpu.AutoReleasePool::new()
  let texture = pool.track_texture(
    self.device.create_texture_rgba8_2d_with_usage(
      layer.width.reinterpret_as_uint(),
      layer.height.reinterpret_as_uint(),
      @wgpu.TextureUsage::from_u64(
        @wgpu.TEXTURE_USAGE_TEXTURE_BINDING | @wgpu.TEXTURE_USAGE_COPY_DST,
      ),
    ),
  )
  self.queue.write_texture_rgba8_2d(
    texture,
    layer.width.reinterpret_as_uint(),
    layer.height.reinterpret_as_uint(),
    layer.pixels,
  )
  let view = pool.track_texture_view(texture.create_view())
  let shader = pool.track_shader_module(
    self.device.create_shader_module_wgsl(surface_text_shader(layer.x, layer.y)),
  )
  let pipeline = pool.track_render_pipeline(
    self.device.create_render_pipeline_color_format(shader, self.format),
  )
  let layout = pool.track_bind_group_layout(pipeline.get_bind_group_layout(0U))
  let bind_group = pool.track_bind_group(
    self.device.create_bind_group_texture_2d(layout, view),
  )
  { pool, pipeline, bind_group, }
}
