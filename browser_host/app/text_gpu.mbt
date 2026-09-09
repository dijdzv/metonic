///|
priv struct TextGpuLayer {
  texture : @dom.GPUTexture
  mut uniform : @dom.GPUBuffer?
  mut group : @dom.GPUBindGroup?
}

///|
priv struct TextGpu {
  device : @dom.GPUDevice
  pipeline : @dom.GPURenderPipeline
  mut layers : Array[TextGpuLayer]
  mut pending : Array[TextGpuLayer]
}

///|
let text_gpu : Ref[TextGpu?] = Ref(None)

///|
fn release_text_layers(layers : Array[TextGpuLayer]) -> Unit {
  for layer in layers {
    layer.texture.destroy()
    if layer.uniform is Some(buffer) {
      buffer.destroy()
    }
  }
  layers.clear()
}

///|
#export_name("text_gpu_dispose")
pub fn text_gpu_dispose() -> Unit {
  if text_gpu.val is Some(gpu) {
    text_gpu.val = None
    release_text_layers(gpu.pending)
    release_text_layers(gpu.layers)
  }
}

///|
#export_name("text_gpu_init")
pub fn text_gpu_init(device : @dom.GPUDevice, format : String) -> Int {
  text_gpu_dispose()
  guard @dom.GPUTextureFormat::from(format) is Some(format) else { return 0 }
  let shader = device.create_shader_module(
    @dom.GPUShaderModuleDescriptor::new(
      (
        #|struct U { viewport: vec2f, origin: vec2f, size: vec2f, tex: vec2f };
        #|@group(0) @binding(0) var<uniform> u: U;
        #|@group(0) @binding(1) var text_tex: texture_2d<f32>;
        #|struct VertexOut { @builtin(position) position: vec4f, @location(0) uv: vec2f };
        #|@vertex fn vs(@builtin(vertex_index) i:u32)->VertexOut { var p=array<vec2f,6>(vec2f(0,0),vec2f(1,0),vec2f(0,1),vec2f(0,1),vec2f(1,0),vec2f(1,1)); let q=u.origin+p[i]*u.size; var out:VertexOut; out.position=vec4f(q.x/u.viewport.x*2-1,1-q.y/u.viewport.y*2,0,1); out.uv=p[i]; return out; }
        #|@fragment fn fs(in:VertexOut)->@location(0) vec4f { let dims=vec2i(textureDimensions(text_tex)); let pos=min(vec2i(in.uv*vec2f(dims)),dims-vec2i(1)); return textureLoad(text_tex,pos,0); }
      ),
    ),
  )
  let pipeline = device.create_render_pipeline(
    @dom.GPURenderPipelineDescriptor::new(
      @dom.GPUAutoLayoutMode::Auto,
      @dom.GPUVertexState::new(shader, entry_point="vs"),
      fragment=@dom.GPUFragmentState::new(
        shader,
        [@dom.GPUColorTargetState::new(format)],
        entry_point="fs",
      ),
    ),
  )
  text_gpu.val = Some({ device, pipeline, layers: [], pending: [], })
  1
}

///|
#export_name("text_gpu_abort")
pub fn text_gpu_abort() -> Unit {
  if text_gpu.val is Some(gpu) {
    release_text_layers(gpu.pending)
  }
}

///|
#export_name("text_gpu_add")
pub fn text_gpu_add(index : Int, pixels : @dom.AllowSharedBufferSource) -> Int {
  guard text_gpu.val is Some(gpu) else { return 0 }
  guard index == gpu.pending.length() && index < @app.view_layer_count() else {
    return 0
  }
  let width = @app.view_layer_field(index, 2).reinterpret_as_uint()
  let height = @app.view_layer_field(index, 3).reinterpret_as_uint()
  let size = @dom.GPUExtent3DDict::new(width, height~)
  let texture = gpu.device.create_texture(
    @dom.GPUTextureDescriptor::new(size, Rgba8unorm, 6U),
  )
  // A later host API call can throw; the JS boundary then aborts this pending batch.
  let layer = TextGpuLayer::{ texture, uniform: None, group: None, }
  gpu.pending.push(layer)
  let uniform = gpu.device.create_buffer(
    @dom.GPUBufferDescriptor::new(32UL, 72U),
  )
  layer.uniform = Some(uniform)
  gpu.device
  .queue()
  .write_texture(
    @dom.GPUTexelCopyTextureInfo::new(texture),
    pixels,
    @dom.GPUTexelCopyBufferLayout::new(bytes_per_row=width * 4U),
    size,
  )
  layer.group = Some(
    gpu.device.create_bind_group(
      @dom.GPUBindGroupDescriptor::new(gpu.pipeline.get_bind_group_layout(0U), [
        @dom.GPUBindGroupEntry::new(0U, @dom.GPUBufferBinding::new(uniform)),
        @dom.GPUBindGroupEntry::new(1U, texture.create_view()),
      ]),
    ),
  )
  1
}

///|
#export_name("text_gpu_commit")
pub fn text_gpu_commit() -> Int {
  guard text_gpu.val is Some(gpu) else { return 0 }
  guard gpu.pending.length() == @app.view_layer_count() else { return 0 }
  release_text_layers(gpu.layers)
  gpu.layers = gpu.pending
  gpu.pending = []
  1
}

///|
#export_name("text_gpu_record")
pub fn text_gpu_record(
  pass : @dom.GPURenderPassEncoder,
  index : Int,
  data : @dom.AllowSharedBufferSource,
) -> Int {
  guard text_gpu.val is Some(gpu) else { return 0 }
  guard index >= 0 && index < gpu.layers.length() else { return 0 }
  let layer = gpu.layers[index]
  guard layer.uniform is Some(uniform) && layer.group is Some(group) else {
    return 0
  }
  gpu.device.queue().write_buffer(uniform, 0UL, data)
  pass.set_pipeline(gpu.pipeline)
  pass.set_bind_group(0U, group)
  pass.draw(6U)
  1
}
