///|
pub struct Layer {
  bounds : @application.Bounds
  pixels : Bytes
}

///|
fn button_layer(
  engine : @raster.Engine,
  item : @application.Element,
  selection? : (Int, Int) = (0, 0),
  caret? : Int? = None,
  single_line_scroll? : Int? = None,
) -> Layer {
  let button = item.bounds
  let label_width = (button.width - 16).max(1)
  let label_top = if button.height < 36 { 2 } else { 4 }
  let label = @raster.render(
    engine,
    item.text,
    label_width,
    32,
    selection~,
    caret~,
    single_line_scroll~,
  )
  let pixels = Bytes::makei(button.width * button.height * 4, i => {
    let x = i / 4 % button.width
    let y = i / 4 / button.width
    if x < 2 || x >= button.width - 2 || y < 2 || y >= button.height - 2 {
      match i % 4 {
        0 => if item.focused { b'\xF5' } else { b'\x35' }
        1 => if item.focused { b'\xA1' } else { b'\x50' }
        2 => if item.focused { b'\x5C' } else { b'\x6D' }
        _ => b'\xFF'
      }
    } else if x >= 8 &&
      x < button.width - 8 &&
      y >= label_top &&
      y < label_top + 32 {
      label[((y - label_top) * label_width + x - 8) * 4 + i % 4]
    } else {
      b'\xFF'
    }
  })
  { bounds: button, pixels, }
}

///|
pub fn render(
  engine : @raster.Engine,
  view : @application.View,
  text : String,
  selection? : (Int, Int) = (0, 0),
  caret? : Int? = None,
  query_scroll? : Int? = None,
) -> Array[Layer] {
  let request_layer = button_layer(engine, view.request)
  let query_layer = button_layer(
    engine,
    view.query,
    selection=view.query_selection,
    caret=view.query_caret,
    single_line_scroll=query_scroll,
  )
  let query_label = Layer::{
    bounds: view.query_label.bounds,
    pixels: @raster.render(engine, view.query_label.text, 32, 32),
  }
  let result = view.result.bounds
  let result_pixels = if view.result.text == "" {
    b""
  } else {
    @raster.render(engine, view.result.text, result.width, result.height)
  }
  let task = view.task_status.bounds
  let start_layer = button_layer(engine, view.start)
  let cancel_layer = button_layer(engine, view.cancel)
  let task_pixels = @raster.render(
    engine,
    view.task_status.text,
    task.width,
    task.height,
  )
  // The editor must remain the retained layout for hit testing and IME.
  let editor = view.editor.bounds
  let editor_pixels = @raster.render(
    engine,
    text,
    editor.width,
    editor.height,
    selection~,
    caret~,
  )
  let layers = [
    Layer::{ bounds: editor, pixels: editor_pixels, },
    request_layer,
  ]
  if !result_pixels.is_empty() {
    layers.push({ bounds: result, pixels: result_pixels, })
  }
  layers.push({ bounds: task, pixels: task_pixels, })
  layers.push(start_layer)
  layers.push(cancel_layer)
  layers.push(query_label)
  layers.push(query_layer)
  layers
}
