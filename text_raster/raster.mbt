///|
pub struct Engine {
  system : @cosmic.FontSystem
  mut cache : @cosmic.SwashCache
  mut layout : @cosmic.Buffer?
  priv layouts : Array[CachedLayout]
  mut layout_builds : Int
  mut layout_hits : Int
  mut paints : Int
  mut text : String
  mut width : Int
  mut single_line : Bool
  mut typography : @theme.Typography
  mut scroll_y : Int
}

///|
priv struct CachedLayout {
  text : String
  width : Int
  single_line : Bool
  typography : @theme.Typography
  buffer : @cosmic.Buffer
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
      layouts: [],
      layout_builds: 0,
      layout_hits: 0,
      paints: 0,
      text: "",
      width: 0,
      single_line: false,
      typography: @theme.default().typography,
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
  theme? : @theme.Theme = @theme.default(),
) -> Bytes {
  if width < 1 || width > 1024 || height < 1 || height > 1024 {
    Bytes::makei(0, _ => b'\x00')
  } else {
    engine.paints += 1
    let single_line = single_line_scroll is Some(_)
    let buffer = match
      engine.layouts
      .iter()
      .find_first(entry => {
        entry.text == text &&
        entry.width == width &&
        entry.single_line == single_line &&
        entry.typography == theme.typography
      }) {
      Some(entry) => {
        engine.layout_hits += 1
        entry.buffer
      }
      None => {
        let attrs = @cosmic.AttrsList::new(
          @cosmic.Attrs::new().family(
            @cosmic.Family::Name(theme.typography.family),
          ),
        )
        let buffer = @cosmic.Buffer::new(
            @cosmic.Metrics::new(
              theme.typography.size,
              theme.typography.line_height,
            ),
          )
          .set_text(text, attrs, @cosmic.Shaping::Advanced)
          .set_size(Some(Float::from_int(width)), None)
          .set_wrap(
            if single_line {
              @cosmic.Wrap::None
            } else {
              @cosmic.Wrap::WordOrGlyph
            },
          )
          .layout_all_with_font_system(engine.system)
        engine.layout_builds += 1
        if engine.layouts.length() == 64 {
          ignore(engine.layouts.remove(0))
        }
        engine.layouts.push({
          text,
          width,
          single_line,
          typography: theme.typography,
          buffer,
        })
        buffer
      }
    }
    engine.layout = Some(buffer)
    engine.text = text
    engine.width = width
    engine.single_line = single_line
    engine.typography = theme.typography
    let mut bottom = 0
    for run in buffer.layout_runs() {
      bottom = bottom.max((run.line_top + run.line_height).ceil().to_int())
    }
    let mut scroll_y = vertical_scroll.max(0).min((bottom - height).max(0))
    if follow_caret is Some(offset) {
      if caret_position(engine, offset, after=caret_after) is Some((_, y)) {
        scroll_y = scroll_y
          .min(y)
          .max(y + theme.typography.line_height.ceil().to_int() - height)
          .max(0)
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
          for
            py in y.max(0)..<(y + theme.typography.line_height.ceil().to_int()).min(
              height,
            ) {
            pixels[py * width + x] = 0
          }
        }
      }
    }
    pack_rgba(pixels, selected, theme~)
  }
}

///|
fn pack_rgba(
  pixels : Array[Int],
  selected : Array[Bool],
  theme? : @theme.Theme = @theme.default(),
) -> Bytes {
  let rgba = FixedArray::make(pixels.length() * 4, b'\xff')
  for index, gray in pixels {
    let offset = index * 4
    let background = if selected[index] {
      theme.selection
    } else {
      theme.background
    }
    rgba[offset] = ((
      gray * background.red.to_int() +
      (255 - gray) * theme.foreground.red.to_int()
    ) /
    255).to_byte()
    rgba[offset + 1] = ((
      gray * background.green.to_int() +
      (255 - gray) * theme.foreground.green.to_int()
    ) /
    255).to_byte()
    rgba[offset + 2] = ((
      gray * background.blue.to_int() +
      (255 - gray) * theme.foreground.blue.to_int()
    ) /
    255).to_byte()
  }
  rgba.unsafe_reinterpret_as_bytes()
}

///|
pub fn Engine::layout_stats(self : Engine) -> (Int, Int) {
  (self.layout_builds, self.layout_hits)
}

///|
pub fn Engine::paint_count(self : Engine) -> Int {
  self.paints
}

///|
pub fn vertical_scroll(engine : Engine) -> Int {
  engine.scroll_y
}

///|
pub fn matches_layout(
  engine : Engine,
  text : String,
  width : Int,
  single_line : Bool,
  typography? : @theme.Typography = @theme.default().typography,
) -> Bool {
  engine.layout is Some(_) &&
  engine.text == text &&
  engine.width == width &&
  engine.single_line == single_line &&
  engine.typography == typography
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
