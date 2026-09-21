///|
fn render_item(engine : @raster.Engine, item : Item) -> Layer {
  let element = item.element
  let bounds = element.bounds
  match item.surface {
    Text => {
      let pixels = @raster.render(
        engine,
        element.text,
        bounds.width,
        bounds.height,
        selection=item.selection,
        selection_ranges?=item.selection_ranges,
        caret=item.caret,
        caret_after=item.caret_after,
        single_line_scroll=item.single_line_scroll,
        vertical_scroll=item.vertical_scroll,
        follow_caret=item.follow_caret,
      )
      { bounds, pixels, }
    }
    Control => {
      let label_width = (bounds.width - 16).max(1)
      let label_top = if bounds.height < 36 { 2 } else { 4 }
      let label = @raster.render(
        engine,
        element.text,
        label_width,
        32,
        selection=item.selection,
        selection_ranges?=item.selection_ranges,
        caret=item.caret,
        caret_after=item.caret_after,
        single_line_scroll=item.single_line_scroll,
        vertical_scroll=item.vertical_scroll,
        follow_caret=item.follow_caret,
      )
      let pixels = Bytes::makei(bounds.width * bounds.height * 4, i => {
        let x = i / 4 % bounds.width
        let y = i / 4 / bounds.width
        if x < 2 || x >= bounds.width - 2 || y < 2 || y >= bounds.height - 2 {
          match i % 4 {
            0 => if element.focused { b'\xF5' } else { b'\x35' }
            1 => if element.focused { b'\xA1' } else { b'\x50' }
            2 => if element.focused { b'\x5C' } else { b'\x6D' }
            _ => b'\xFF'
          }
        } else if x >= 8 &&
          x < bounds.width - 8 &&
          y >= label_top &&
          y < label_top + 32 {
          label[((y - label_top) * label_width + x - 8) * 4 + i % 4]
        } else {
          b'\xFF'
        }
      })
      { bounds, pixels, }
    }
  }
}

///|
pub fn render(
  engine : @raster.Engine,
  items : Array[Item],
  retain_layout? : Int,
) -> Result[Array[Layer], String] {
  if retain_layout is Some(index) && (index < 0 || index >= items.length()) {
    return Err("invalid_retained_item")
  }
  for item in items {
    let bounds = item.element.bounds
    if bounds.width < 1 ||
      bounds.width > 1024 ||
      bounds.height < 1 ||
      bounds.height > 1024 {
      return Err("invalid_item_bounds")
    }
  }
  let layers : Array[Layer] = items.map(item => {
    bounds: item.element.bounds,
    pixels: b"",
  })
  for index = 0; index < items.length(); index = index + 1 {
    if retain_layout != Some(index) {
      layers[index] = render_item(engine, items[index])
    }
  }
  // Hit testing must retain the requested input, not the last composited label.
  if retain_layout is Some(index) {
    layers[index] = render_item(engine, items[index])
  }
  Ok(layers)
}
