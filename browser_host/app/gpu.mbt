///|
let gpu : @gpu_renderer.Session = @gpu_renderer.create()

///|
#export_name("scene_gpu_dispose")
pub fn scene_gpu_dispose() -> Unit {
  gpu.scene_gpu_dispose()
}

///|
#export_name("scene_gpu_init")
pub fn scene_gpu_init(
  device : @input_dom.GPUDevice,
  format : String,
) -> @gpu_renderer.GpuInitPromise {
  gpu.scene_gpu_init(device, format)
}

///|
#export_name("scene_gpu_record")
pub fn scene_gpu_record(
  pass : @input_dom.GPURenderPassEncoder,
  data : @input_dom.ArrayBufferView,
) -> Int {
  gpu.scene_gpu_record(pass, data)
}

///|
#export_name("text_gpu_dispose")
pub fn text_gpu_dispose() -> Unit {
  gpu.text_gpu_dispose()
}

///|
#export_name("text_gpu_init")
pub fn text_gpu_init(device : @input_dom.GPUDevice, format : String) -> Int {
  gpu.text_gpu_init(device, format)
}

///|
#export_name("text_gpu_abort")
pub fn text_gpu_abort() -> Unit {
  gpu.text_gpu_abort()
}

///|
#export_name("text_gpu_add")
pub fn text_gpu_add(index : Int, pixels : @input_dom.ArrayBufferView) -> Int {
  if index < 0 || index >= @app.view_layer_count() {
    return 0
  }
  gpu.text_gpu_add(
    index,
    @app.view_layer_field(index, 2),
    @app.view_layer_field(index, 3),
    pixels,
  )
}

///|
#export_name("text_gpu_commit")
pub fn text_gpu_commit() -> Int {
  gpu.text_gpu_commit(@app.view_layer_count())
}

///|
#export_name("text_gpu_record")
pub fn text_gpu_record(
  pass : @input_dom.GPURenderPassEncoder,
  index : Int,
  data : @input_dom.ArrayBufferView,
) -> Int {
  gpu.text_gpu_record(pass, index, data)
}

///|
#export_name("gpu_frame_abort")
pub fn gpu_frame_abort() -> Unit {
  gpu.gpu_frame_abort()
}

///|
#export_name("gpu_frame_begin")
pub fn gpu_frame_begin(context : @input_dom.GPUCanvasContext) -> Int {
  gpu.gpu_frame_begin(context)
}

///|
#export_name("gpu_frame_scene")
pub fn gpu_frame_scene(data : @input_dom.ArrayBufferView) -> Int {
  gpu.gpu_frame_scene(data)
}

///|
#export_name("gpu_frame_text")
pub fn gpu_frame_text(index : Int, data : @input_dom.ArrayBufferView) -> Int {
  gpu.gpu_frame_text(index, data)
}

///|
#export_name("gpu_frame_submit")
pub fn gpu_frame_submit() -> Int {
  gpu.gpu_frame_submit()
}
