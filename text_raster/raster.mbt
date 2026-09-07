///|
pub struct Engine {
  system : @cosmic.FontSystem
  mut cache : @cosmic.SwashCache
  mut layout : @cosmic.Buffer?
  mut text : String
}

///|
pub fn create(font : Bytes) -> Engine? {
  let system = @cosmic.FontSystem::new_with_locale("ja-JP").load_font_data(font)
  if system.fonts().length() == 0 {
    None
  } else {
    Some({ system, cache: @cosmic.SwashCache::new(), layout: None, text: "", })
  }
}

///|
pub fn render(
  engine : Engine,
  text : String,
  width : Int,
  height : Int,
  selection? : (Int, Int) = (0, 0),
  caret? : Int? = None,
) -> Bytes {
  if width < 1 || width > 1024 || height < 1 || height > 96 {
    Bytes::makei(0, _ => b'\x00')
  } else {
    let mut buffer = @cosmic.Buffer::new(@cosmic.Metrics::new(24.0F, 32.0F))
    let attrs = @cosmic.AttrsList::new(
      @cosmic.Attrs::new().family(@cosmic.Family::Name("Noto Sans JP")),
    )
    buffer = buffer
      .set_text(text, attrs, @cosmic.Shaping::Advanced)
      .set_size(Some(Float::from_int(width)), Some(Float::from_int(height)))
      .set_wrap(@cosmic.Wrap::WordOrGlyph)
      .layout_all_with_font_system(engine.system)
    engine.layout = Some(buffer)
    engine.text = text
    let pixels : Array[Int] = Array::make(width * height, 255)
    let selected : Array[Bool] = Array::make(width * height, false)
    let (start, end) = selection
    if start >= 0 && start < end && end <= text.length() {
      let first = selection_cursor(text, start)
      let last = selection_cursor(text, end)
      for run in buffer.layout_runs() {
        if run.highlight(first, last) is Some((left, span)) {
          let x0 = left.floor().to_int().max(0)
          let x1 = (left + span).ceil().to_int().min(width)
          let y0 = run.line_top.floor().to_int().max(0)
          let y1 = (run.line_top + run.line_height).ceil().to_int().min(height)
          for y in y0..<y1 {
            for x in x0..<x1 {
              selected[y * width + x] = true
            }
          }
        }
      }
    }
    let color = @cosmic.Color::rgb(b'\x00', b'\x00', b'\x00')
    let (_, next_cache) = buffer.draw(engine.system, engine.cache, color, (
      x : Int,
      y : Int,
      w : UInt,
      h : UInt,
      ink : @cosmic.Color,
    ) => {
      let alpha = ink.a().to_int()
      if alpha > 0 {
        let x0 = x.max(0)
        let y0 = y.max(0)
        let x1 = (x + w.reinterpret_as_int()).min(width)
        let y1 = (y + h.reinterpret_as_int()).min(height)
        let mut py = y0
        while py < y1 {
          let mut px = x0
          while px < x1 {
            let index = py * width + px
            pixels[index] = (pixels[index] * (255 - alpha) + 127) / 255
            px += 1
          }
          py += 1
        }
      }
    })
    engine.cache = next_cache
    if caret is Some(offset) {
      if caret_position(engine, offset) is Some((x, y)) {
        if x >= 0 {
          let x = x.min(width - 1)
          for py in y.max(0)..<(y + 32).min(height) {
            pixels[py * width + x] = 0
          }
        }
      }
    }
    Bytes::makei(width * height * 4, i => {
      if i % 4 == 3 {
        b'\xff'
      } else {
        let background = if selected[i / 4] {
          match i % 4 {
            0 => 180
            1 => 210
            _ => 255
          }
        } else {
          255
        }
        (pixels[i / 4] * background / 255).to_byte()
      }
    })
  }
}

///|
fn selection_cursor(text : String, offset : Int) -> @cosmic.Cursor {
  let mut remaining = offset
  let mut line_index = 0
  for line in text.split("\n") {
    if remaining <= line.length() {
      return @cosmic.Cursor::new(line_index, remaining)
    }
    remaining -= line.length() + 1
    line_index += 1
  }
  @cosmic.Cursor::new(line_index, 0)
}

///|
pub fn hit(engine : Engine, x : Int, y : Int) -> Int? {
  let buffer = match engine.layout {
    Some(value) => value
    None => return None
  }
  let cursor = match buffer.hit(Float::from_int(x), Float::from_int(y)) {
    Some(value) => value
    None => return None
  }
  let mut offset = 0
  let mut index = 0
  for line in engine.text.split("\n") {
    if index == cursor.line {
      return Some(offset + cursor.index)
    }
    offset += line.length() + 1
    index += 1
  }
  None
}

///|
pub fn caret_position(engine : Engine, offset : Int) -> (Int, Int)? {
  if offset < 0 || offset > engine.text.length() {
    return None
  }
  match engine.layout {
    None => None
    Some(buffer) =>
      @cosmic.Editor::new(buffer)
      .set_cursor(selection_cursor(engine.text, offset))
      .cursor_position()
  }
}
