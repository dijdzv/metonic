///|
priv struct GpuFrame {
  device : @input_dom.GPUDevice
  encoder : @input_dom.GPUCommandEncoder
  pass : @input_dom.GPURenderPassEncoder
}

///|
let gpu_frame : Ref[GpuFrame?] = Ref(None)

///|
#export_name("gpu_frame_abort")
pub fn gpu_frame_abort() -> Unit {
  // Unfinished command encoders have no destroy API; never finish or submit them.
  gpu_frame.val = None
}

///|
#export_name("gpu_frame_begin")
pub fn gpu_frame_begin(context : @input_dom.GPUCanvasContext) -> Int {
  guard gpu_frame.val is None else { return 0 }
  guard scene_gpu.val is Some(gpu) && gpu.live else { return 0 }
  guard gpu.pipeline is Some(_) else { return 0 }
  let encoder = gpu.device.create_command_encoder()
  let pass = gpu_begin_pass(context, encoder)
  gpu_frame.val = Some({ device: gpu.device, encoder, pass, })
  1
}

///|
#export_name("gpu_frame_scene")
pub fn gpu_frame_scene(data : @input_dom.ArrayBufferView) -> Int {
  guard gpu_frame.val is Some(frame) else { return 0 }
  let result = scene_gpu_record(frame.pass, data)
  if result == 0 {
    gpu_frame_abort()
  }
  result
}

///|
#export_name("gpu_frame_text")
pub fn gpu_frame_text(index : Int, data : @input_dom.ArrayBufferView) -> Int {
  guard gpu_frame.val is Some(frame) else { return 0 }
  let result = text_gpu_record(frame.pass, index, data)
  if result == 0 {
    gpu_frame_abort()
  }
  result
}

///|
#export_name("gpu_frame_submit")
pub fn gpu_frame_submit() -> Int {
  guard gpu_frame.val is Some(frame) else { return 0 }
  gpu_frame.val = None
  frame.pass.end()
  gpu_submit(frame.device, frame.encoder.finish())
  1
}
