///|
#export_name("verify_sessions")
pub fn verify_sessions(
  device : @dom.GPUDevice,
  context : @dom.GPUCanvasContext,
  format : String,
  pixels : @dom.ArrayBufferView,
  uniform : @dom.ArrayBufferView,
) -> Int {
  let first = @gpu_renderer.create()
  let second = @gpu_renderer.create()
  defer {
    first.text_gpu_dispose()
    second.text_gpu_dispose()
  }
  if first.text_gpu_init(device, format) != 1 ||
    second.text_gpu_init(device, format) != 1 {
    return 2
  }
  if first.text_gpu_add(0, 1, 1, pixels) != 1 || first.text_gpu_commit(1) != 1 {
    return 3
  }
  if second.text_gpu_add(0, 1, 1, pixels) != 1 || second.text_gpu_commit(1) != 1 {
    return 4
  }
  if first.gpu_frame_begin(context) != 1 || second.gpu_frame_begin(context) != 1 {
    return 5
  }
  if first.gpu_frame_text(0, uniform) != 1 ||
    second.gpu_frame_text(0, uniform) != 1 {
    return 6
  }
  first.text_gpu_dispose()
  if first.gpu_frame_submit() != 0 {
    return 7
  }
  if second.gpu_frame_submit() != 1 {
    return 8
  }
  if second.gpu_frame_begin(context) != 1 ||
    second.gpu_frame_text(0, uniform) != 1 {
    return 9
  }
  if second.gpu_frame_submit() != 1 {
    return 10
  }
  second.text_gpu_dispose()
  if second.gpu_frame_begin(context) != 0 {
    return 11
  }
  1
}
