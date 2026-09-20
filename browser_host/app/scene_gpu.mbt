///|
priv struct SceneGpu {
  device : @input_dom.GPUDevice
  mut live : Bool
  mut pipeline : @input_dom.GPURenderPipeline?
  mut uniform : @input_dom.GPUBuffer?
  mut group : @input_dom.GPUBindGroup?
}

///|
let scene_gpu : Ref[SceneGpu?] = Ref(None)

///|
#export_name("scene_gpu_dispose")
pub fn scene_gpu_dispose() -> Unit {
  gpu_frame_abort()
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
  device : @input_dom.GPUDevice,
  format : String,
) -> GpuInitPromise {
  scene_gpu_dispose()
  guard @input_dom.GPUTextureFormat::from_string(format) is Some(format) else {
    return gpu_resolve(0)
  }
  let gpu = SceneGpu::{
    device,
    live: true,
    pipeline: None,
    uniform: None,
    group: None,
  }
  scene_gpu.val = Some(gpu)
  let shader = gpu_shader(
    device,
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
  )
  gpu_pipeline_then(
    device.create_render_pipeline_async(gpu_pipeline_descriptor(shader, format)),
    fn(pipeline) {
      if !gpu.live {
        return 0
      }
      gpu.pipeline = Some(pipeline)
      let uniform = gpu_uniform(device)
      gpu.uniform = Some(uniform)
      gpu.group = Some(gpu_group(device, pipeline, uniform, None))
      1
    },
  )
}

///|
#export_name("scene_gpu_record")
pub fn scene_gpu_record(
  pass : @input_dom.GPURenderPassEncoder,
  data : @input_dom.ArrayBufferView,
) -> Int {
  guard scene_gpu.val is Some(gpu) && gpu.live else { return 0 }
  guard gpu.pipeline is Some(pipeline) &&
    gpu.uniform is Some(uniform) &&
    gpu.group is Some(group) else {
    return 0
  }
  gpu_record(gpu.device, uniform, data, pass, pipeline, group)
  1
}
