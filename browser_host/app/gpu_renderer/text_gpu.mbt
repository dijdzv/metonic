///|
priv struct TextGpuLayer {
  texture : @input_dom.GPUTexture
  mut uniform : @input_dom.GPUBuffer?
  mut group : @input_dom.GPUBindGroup?
}

///|
priv struct TextGpu {
  device : @input_dom.GPUDevice
  pipeline : @input_dom.GPURenderPipeline
  mut layers : Array[TextGpuLayer]
  mut pending : Array[TextGpuLayer]
}

///|

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
pub fn Session::text_gpu_dispose(self : Session) -> Unit {
  self.gpu_frame_abort()
  if self.text_gpu.val is Some(gpu) {
    self.text_gpu.val = None
    release_text_layers(gpu.pending)
    release_text_layers(gpu.layers)
  }
}

///|
pub fn Session::text_gpu_init(
  self : Session,
  device : @input_dom.GPUDevice,
  format : String,
) -> Int {
  self.text_gpu_dispose()
  guard @input_dom.GPUTextureFormat::from_string(format) is Some(format) else {
    return 0
  }
  let shader = gpu_shader(
    device,
    (
      #|struct U { viewport: vec2f, origin: vec2f, size: vec2f, tex: vec2f };
      #|@group(0) @binding(0) var<uniform> u: U;
      #|@group(0) @binding(1) var text_tex: texture_2d<f32>;
      #|struct VertexOut { @builtin(position) position: vec4f, @location(0) uv: vec2f };
      #|@vertex fn vs(@builtin(vertex_index) i:u32)->VertexOut { var p=array<vec2f,6>(vec2f(0,0),vec2f(1,0),vec2f(0,1),vec2f(0,1),vec2f(1,0),vec2f(1,1)); let q=u.origin+p[i]*u.size; var out:VertexOut; out.position=vec4f(q.x/u.viewport.x*2-1,1-q.y/u.viewport.y*2,0,1); out.uv=p[i]; return out; }
      #|@fragment fn fs(in:VertexOut)->@location(0) vec4f { let dims=vec2i(textureDimensions(text_tex)); let pos=min(vec2i(in.uv*vec2f(dims)),dims-vec2i(1)); return textureLoad(text_tex,pos,0); }
    ),
  )
  let pipeline = device.create_render_pipeline(
    gpu_pipeline_descriptor(shader, format),
  )
  self.text_gpu.val = Some({ device, pipeline, layers: [], pending: [], })
  1
}

///|
pub fn Session::text_gpu_abort(self : Session) -> Unit {
  if self.text_gpu.val is Some(gpu) {
    release_text_layers(gpu.pending)
  }
}

///|
pub fn Session::text_gpu_add(
  self : Session,
  index : Int,
  width : Int,
  height : Int,
  pixels : @input_dom.ArrayBufferView,
) -> Int {
  guard self.text_gpu.val is Some(gpu) else { return 0 }
  guard index == gpu.pending.length() &&
    width > 0 &&
    width <= 1024 &&
    height > 0 &&
    height <= 1024 else {
    return 0
  }
  let texture = gpu_texture(gpu.device, width, height)
  // A later host API call can throw; the JS boundary then aborts this pending batch.
  let layer = TextGpuLayer::{ texture, uniform: None, group: None, }
  gpu.pending.push(layer)
  let uniform = gpu_uniform(gpu.device)
  layer.uniform = Some(uniform)
  gpu_upload_texture(gpu.device, texture, pixels, width, height)
  layer.group = Some(
    gpu_group(gpu.device, gpu.pipeline, uniform, Some(texture)),
  )
  1
}

///|
pub fn Session::text_gpu_commit(self : Session, expected_count : Int) -> Int {
  guard self.text_gpu.val is Some(gpu) else { return 0 }
  guard gpu.pending.length() == expected_count else { return 0 }
  release_text_layers(gpu.layers)
  gpu.layers = gpu.pending
  gpu.pending = []
  1
}

///|
pub fn Session::text_gpu_record(
  self : Session,
  pass : @input_dom.GPURenderPassEncoder,
  index : Int,
  data : @input_dom.ArrayBufferView,
) -> Int {
  guard self.text_gpu.val is Some(gpu) else { return 0 }
  guard index >= 0 && index < gpu.layers.length() else { return 0 }
  let layer = gpu.layers[index]
  guard layer.uniform is Some(uniform) && layer.group is Some(group) else {
    return 0
  }
  gpu_record(gpu.device, uniform, data, pass, gpu.pipeline, group)
  1
}
