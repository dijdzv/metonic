///|
pub struct Engine {
  system : @cosmic.FontSystem
  mut cache : @cosmic.SwashCache
  mut layout : @cosmic.Buffer?
  mut text : String
  mut scroll_y : Int
}

///|
pub fn create(font : Bytes) -> Engine? {
  let system = @cosmic.FontSystem::new_with_locale("ja-JP").load_font_data(font)
  if system.fonts().length() == 0 {
    None
  } else {
    Some({
      system,
      cache: @cosmic.SwashCache::new(),
      layout: None,
      text: "",
      scroll_y: 0,
    })
  }
}

///|
pub fn render(
  engine : Engine,
  text : String,
  width : Int,
  height : Int,
  selection? : (Int, Int) = (0, 0),
  selection_ranges? : Array[(Int, Int)],
  caret? : Int? = None,
  caret_after? : Bool = false,
  single_line_scroll? : Int? = None,
  vertical_scroll? : Int = 0,
  follow_caret? : Int? = None,
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
      .set_size(Some(Float::from_int(width)), None)
      .set_wrap(
        if single_line_scroll is Some(_) {
          @cosmic.Wrap::None
        } else {
          @cosmic.Wrap::WordOrGlyph
        },
      )
      .layout_all_with_font_system(engine.system)
    engine.layout = Some(buffer)
    engine.text = text
    let mut bottom = 0
    for run in buffer.layout_runs() {
      bottom = bottom.max((run.line_top + run.line_height).ceil().to_int())
    }
    let mut scroll_y = vertical_scroll.max(0).min((bottom - height).max(0))
    if follow_caret is Some(offset) {
      if caret_position(engine, offset, after=caret_after) is Some((_, y)) {
        scroll_y = scroll_y.min(y).max(y + 32 - height).max(0)
      }
    }
    engine.scroll_y = scroll_y
    let scroll_x = single_line_scroll.unwrap_or(0).max(0)
    let pixels : Array[Int] = Array::make(width * height, 255)
    let selected : Array[Bool] = Array::make(width * height, false)
    for range in selection_ranges.unwrap_or([selection]) {
      let (start, end) = range
      if start >= 0 && start < end && end <= text.length() {
        let first = selection_cursor(text, start)
        let last = selection_cursor(text, end)
        for run in buffer.layout_runs() {
          if run.highlight(first, last) is Some((left, span)) {
            let x0 = (left.floor().to_int() - scroll_x).max(0)
            let x1 = ((left + span).ceil().to_int() - scroll_x).min(width)
            let y0 = (run.line_top.floor().to_int() - scroll_y).max(0)
            let y1 = ((run.line_top + run.line_height).ceil().to_int() -
            scroll_y).min(height)
            for y in y0..<y1 {
              for x in x0..<x1 {
                selected[y * width + x] = true
              }
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
        let x = x - scroll_x
        let y = y - scroll_y
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
      if caret_position(engine, offset, after=caret_after) is Some((x, y)) {
        let x = x - scroll_x
        let y = y - scroll_y
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
pub fn vertical_scroll(engine : Engine) -> Int {
  engine.scroll_y
}

///|
fn selection_cursor(
  text : String,
  offset : Int,
  after? : Bool = false,
) -> @cosmic.Cursor {
  let mut remaining = offset
  let mut line_index = 0
  for line in text.split("\n") {
    if remaining <= line.length() {
      return @cosmic.Cursor::new_with_affinity(
        line_index,
        remaining,
        if after {
          After
        } else {
          Before
        },
      )
    }
    remaining -= line.length() + 1
    line_index += 1
  }
  @cosmic.Cursor::new(line_index, 0)
}

///|
pub fn hit(engine : Engine, x : Int, y : Int) -> Int? {
  hit_caret(engine, x, y).map(position => position.0)
}

///|
pub fn hit_caret(engine : Engine, x : Int, y : Int) -> (Int, Bool)? {
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
      return Some((offset + cursor.index, cursor.affinity.after()))
    }
    offset += line.length() + 1
    index += 1
  }
  None
}

///|
pub fn caret_position(
  engine : Engine,
  offset : Int,
  after? : Bool = false,
) -> (Int, Int)? {
  if offset < 0 || offset > engine.text.length() {
    return None
  }
  match engine.layout {
    None => None
    Some(buffer) =>
      @cosmic.Editor::new(buffer)
      .set_cursor(selection_cursor(engine.text, offset, after~))
      .cursor_position()
  }
}
