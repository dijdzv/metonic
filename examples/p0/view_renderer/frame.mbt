///|
pub struct Layer {
  bounds : @application.Bounds
  pixels : Bytes
}

///|
pub fn render(
  engine : @raster.Engine,
  view : @application.View,
  text : String,
  selection? : (Int, Int) = (0, 0),
  caret? : Int? = None,
) -> Array[Layer] {
  let button = view.request.bounds
  let label_width = (button.width - 16).max(1)
  let label = @raster.render(engine, view.request.text, label_width, 32)
  let button_pixels = Bytes::makei(button.width * button.height * 4, i => {
    let x = i / 4 % button.width
    let y = i / 4 / button.width
    if x < 2 || x >= button.width - 2 || y < 2 || y >= button.height - 2 {
      match i % 4 {
        0 => if view.request.focused { b'\xF5' } else { b'\x35' }
        1 => if view.request.focused { b'\xA1' } else { b'\x50' }
        2 => if view.request.focused { b'\x5C' } else { b'\x6D' }
        _ => b'\xFF'
      }
    } else if x >= 8 && x < button.width - 8 && y >= 4 && y < 36 {
      label[((y - 4) * label_width + x - 8) * 4 + i % 4]
    } else {
      b'\xFF'
    }
  })
  let result = view.result.bounds
  let result_pixels = if view.result.text == "" {
    b""
  } else {
    @raster.render(engine, view.result.text, result.width, result.height)
  }
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
    Layer::{ bounds: button, pixels: button_pixels, },
  ]
  if !result_pixels.is_empty() {
    layers.push({ bounds: result, pixels: result_pixels, })
  }
  layers
}
