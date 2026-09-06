///|
pub struct Engine {
  system : @cosmic.FontSystem
  mut cache : @cosmic.SwashCache
}

///|
pub fn create(font : Bytes) -> Engine? {
  let system = @cosmic.FontSystem::new_with_locale("ja-JP").load_font_data(font)
  if system.fonts().length() == 0 {
    None
  } else {
    Some({ system, cache: @cosmic.SwashCache::new(), })
  }
}

///|
pub fn render(
  engine : Engine,
  text : String,
  width : Int,
  height : Int,
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
    let pixels : Array[Int] = Array::make(width * height, 255)
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
    Bytes::makei(width * height * 4, i => {
      if i % 4 == 3 {
        b'\xff'
      } else {
        pixels[i / 4].to_byte()
      }
    })
  }
}
