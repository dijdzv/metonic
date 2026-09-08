///|
let rendered_editor : Ref[(String, Bytes, Int)?] = Ref(None)

///|
#export_name("editor_render")
pub fn editor_render(viewport_width : Int) -> Int {
  let engine = match bridge.engine {
    Some(engine) => engine
    None => return 0
  }
  let width = (viewport_width - 16).max(1).min(640)
  let text = editor_display()
  let key = (text, application.val.result_utf8, width)
  if rendered_editor.val == Some(key) {
    return 2
  }
  // Rendering the result last would replace the retained editor layout.
  let status = if application.val.result_utf8.is_empty() {
    b""
  } else {
    @raster.render(
      engine,
      @utf8.decode_lossy(application.val.result_utf8).trim().to_owned(),
      width,
      32,
    )
  }
  let pixels = @raster.render(engine, text, width, 96)
  bridge.output = Some(
    Bytes::makei(pixels.length() + status.length(), index => {
      if index < pixels.length() {
        pixels[index]
      } else {
        status[index - pixels.length()]
      }
    }),
  )
  bridge.output_width = width
  rendered_editor.val = Some(key)
  1
}

///|
#export_name("text_height")
pub fn text_height() -> Int {
  match bridge.output {
    Some(bytes) if bridge.output_width > 0 =>
      bytes.length() / (bridge.output_width * 4)
    _ => 0
  }
}
