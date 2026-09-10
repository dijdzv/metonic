///|
priv struct SceneGpu {
  device : @dom.GPUDevice
  mut live : Bool
  mut pipeline : @dom.GPURenderPipeline?
  mut uniform : @dom.GPUBuffer?
  mut group : @dom.GPUBindGroup?
}

///|
let scene_gpu : Ref[SceneGpu?] = Ref(None)

///|
#export_name("scene_gpu_dispose")
pub fn scene_gpu_dispose() -> Unit {
  if scene_gpu.val is Some(gpu) {
    scene_gpu.val = None
    gpu.live = false
    if gpu.uniform is Some(buffer) {
      buffer.destroy()
      gpu.uniform = None
    }
    gpu.pipeline = None
    gpu.group = None
  }
}

///|
#export_name("scene_gpu_init")
pub fn scene_gpu_init(
  device : @dom.GPUDevice,
  format : String,
) -> @dom.JsPromise[Int] {
  scene_gpu_dispose()
  guard @dom.GPUTextureFormat::from(format) is Some(format) else {
    return @dom.JsPromise::resolve(0)
  }
  let gpu = SceneGpu::{
    device,
    live: true,
    pipeline: None,
    uniform: None,
    group: None,
  }
  scene_gpu.val = Some(gpu)
  let shader = device.create_shader_module(
    @dom.GPUShaderModuleDescriptor::new(
      (
        #|struct U { rect: vec4f, viewport: vec2f, enabled: f32, pad: f32 };
        #|@group(0) @binding(0) var<uniform> u: U;
        #|@vertex fn vs(@builtin(vertex_index) i: u32) -> @builtin(position) vec4f {
        #|  var p = array<vec2f, 6>(vec2f(0,0), vec2f(1,0), vec2f(0,1), vec2f(0,1), vec2f(1,0), vec2f(1,1));
        #|  let px = u.rect.xy + p[i] * u.rect.zw;
        #|  let clip = vec2f(px.x / u.viewport.x * 2.0 - 1.0, 1.0 - px.y / u.viewport.y * 2.0);
        #|  return vec4f(clip, 0, 1);
        #|}
        #|@fragment fn fs() -> @location(0) vec4f {
        #|  return select(vec4f(0.08, 0.65, 0.68, 1), vec4f(0.95, 0.38, 0.10, 1), u.enabled > 0.5);
        #|}
      ),
    ),
  )
  device
  .create_render_pipeline_async(
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
  .then(fn(pipeline) {
    if !gpu.live {
      return 0
    }
    gpu.pipeline = Some(pipeline)
    let uniform = device.create_buffer(@dom.GPUBufferDescriptor::new(32UL, 72U))
    gpu.uniform = Some(uniform)
    gpu.group = Some(
      device.create_bind_group(
        @dom.GPUBindGroupDescriptor::new(pipeline.get_bind_group_layout(0U), [
          @dom.GPUBindGroupEntry::new(0U, @dom.GPUBufferBinding::new(uniform)),
        ]),
      ),
    )
    1
  })
}

///|
#export_name("scene_gpu_record")
pub fn scene_gpu_record(
  pass : @dom.GPURenderPassEncoder,
  data : @dom.AllowSharedBufferSource,
) -> Int {
  guard scene_gpu.val is Some(gpu) && gpu.live else { return 0 }
  guard gpu.pipeline is Some(pipeline) &&
    gpu.uniform is Some(uniform) &&
    gpu.group is Some(group) else {
    return 0
  }
  gpu.device.queue().write_buffer(uniform, 0UL, data)
  pass.set_pipeline(pipeline)
  pass.set_bind_group(0U, group)
  pass.draw(6U)
  1
}
