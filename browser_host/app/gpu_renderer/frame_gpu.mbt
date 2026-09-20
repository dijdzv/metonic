///|
priv struct GpuFrame {
  device : @input_dom.GPUDevice
  encoder : @input_dom.GPUCommandEncoder
  pass : @input_dom.GPURenderPassEncoder
}

///|

///|
pub fn Session::gpu_frame_abort(self : Session) -> Unit {
  // Unfinished command encoders have no destroy API; never finish or submit them.
  self.gpu_frame.val = None
}

///|
pub fn Session::gpu_frame_begin(
  self : Session,
  context : @input_dom.GPUCanvasContext,
) -> Int {
  guard self.gpu_frame.val is None else { return 0 }
  let device = match self.scene_gpu.val {
    Some(gpu) if gpu.live && gpu.pipeline is Some(_) => gpu.device
    Some(_) => return 0
    None =>
      match self.text_gpu.val {
        Some(gpu) => gpu.device
        None => return 0
      }
  }
  let encoder = device.create_command_encoder()
  let pass = gpu_begin_pass(context, encoder)
  self.gpu_frame.val = Some({ device, encoder, pass, })
  1
}

///|
pub fn Session::gpu_frame_scene(
  self : Session,
  data : @input_dom.ArrayBufferView,
) -> Int {
  guard self.gpu_frame.val is Some(frame) else { return 0 }
  let result = self.scene_gpu_record(frame.pass, data)
  if result == 0 {
    self.gpu_frame_abort()
  }
  result
}

///|
pub fn Session::gpu_frame_text(
  self : Session,
  index : Int,
  data : @input_dom.ArrayBufferView,
) -> Int {
  guard self.gpu_frame.val is Some(frame) else { return 0 }
  let result = self.text_gpu_record(frame.pass, index, data)
  if result == 0 {
    self.gpu_frame_abort()
  }
  result
}

///|
pub fn Session::gpu_frame_submit(self : Session) -> Int {
  guard self.gpu_frame.val is Some(frame) else { return 0 }
  self.gpu_frame.val = None
  frame.pass.end()
  gpu_submit(frame.device, frame.encoder.finish())
  1
}
