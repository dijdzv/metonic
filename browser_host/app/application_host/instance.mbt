///|
#external
pub type Instance

///|
pub fn create(
  application : @app.Application,
  bindings : Array[Binding],
  canvas_id~ : String,
  event_name~ : String,
  font_url~ : String,
  font_sha256~ : String,
) -> Instance {
  let session = Session::{
    application,
    bindings,
    canvas_id,
    event_name,
    font: @font_loader.create(font_url, font_sha256).unwrap(),
    gpu: @gpu_renderer.create(),
    editors: [],
    inputs: None,
    engine: None,
    layers: [],
    stopped: false,
    tasks: @task_driver.driver(),
  }
  @async.run_async_main(async fn() { session.run_tasks() })
  make_bridge(
    () => if session.stopped { rejected_font() } else { session.font.fetch() },
    buffer => {
      if session.stopped {
        return 0
      }
      guard buffer.to_bytes() is Some(bytes) else { return 0 }
      session.engine = @raster.create(bytes)
      if session.engine is Some(_) {
        1
      } else {
        0
      }
    },
    (device, format) => session.start(device, format),
    (width, height) => session.resize(width, height),
    () => session.render(),
    index => session.activate(index),
    () => session.layers.length(),
    (index, field) => {
      if index < 0 || index >= session.layers.length() {
        return -1
      }
      let bounds = session.layers[index].bounds
      match field {
        0 => bounds.x
        1 => bounds.y
        2 => bounds.width
        3 => bounds.height
        _ => -1
      }
    },
    index => transfer(session.layers[index].pixels),
    () => session.gpu.text_gpu_abort(),
    (index, pixels) => {
      if session.stopped || index < 0 || index >= session.layers.length() {
        return 0
      }
      let bounds = session.layers[index].bounds
      session.gpu.text_gpu_add(index, bounds.width, bounds.height, pixels)
    },
    () => {
      if session.stopped {
        0
      } else {
        session.gpu.text_gpu_commit(session.layers.length())
      }
    },
    context => {
      if session.stopped {
        0
      } else {
        session.gpu.gpu_frame_begin(context)
      }
    },
    (index, data) => session.gpu.gpu_frame_text(index, data),
    () => session.gpu.gpu_frame_submit(),
    () => session.gpu.gpu_frame_abort(),
    () => session.stop(),
    () => if session.stopped || (application.can_close)() { 1 } else { 0 },
  )
}
