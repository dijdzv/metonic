///|
fn render_item(engine : @raster.Engine, item : Item) -> Layer {
  let element = item.element
  let bounds = element.bounds
  let layer = match item.surface {
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
      let pixels = control_pixels(bounds, label, label_top, element.focused)
      { bounds, pixels, }
    }
    Checkbox(checked~, enabled~, invalid~) => {
      let label_width = (bounds.width - 44).max(1)
      let label_top = if bounds.height < 36 { 2 } else { 4 }
      let label = @raster.render(engine, element.text, label_width, 32)
      let pixels = checkbox_pixels(
        bounds,
        label,
        label_top,
        element.focused,
        checked,
        enabled,
        invalid,
      )
      { bounds, pixels, }
    }
  }
  clip_layer(layer, item.clip)
}

///|
fn checkbox_pixels(
  bounds : @view.Bounds,
  label : Bytes,
  label_top : Int,
  focused : Bool,
  checked : Bool,
  enabled : Bool,
  invalid : Bool,
) -> Bytes {
  let width = bounds.width
  let height = bounds.height
  let label_width = (width - 44).max(1)
  let rgba = FixedArray::make(width * height * 4, b'\xff')
  let border_r = if invalid {
    b'\xC4'
  } else if focused {
    b'\xF5'
  } else {
    b'\x35'
  }
  let border_g = if invalid {
    b'\x3C'
  } else if focused {
    b'\xA1'
  } else {
    b'\x50'
  }
  let border_b = if invalid {
    b'\x3C'
  } else if focused {
    b'\x5C'
  } else {
    b'\x6D'
  }
  let box_y = ((height - 20) / 2).max(2)
  for y in 0..<height {
    for x in 0..<width {
      let index = (y * width + x) * 4
      let outer = x < 2 || x >= width - 2 || y < 2 || y >= height - 2
      let bx = x - 8
      let by = y - box_y
      let inside = bx >= 0 && bx < 20 && by >= 0 && by < 20
      let edge = inside && (bx < 2 || bx >= 18 || by < 2 || by >= 18)
      let mark = checked &&
        inside &&
        (
          (bx >= 5 && bx <= 9 && (by - bx - 5).abs() <= 1) ||
          (bx >= 9 && bx <= 17 && (by + bx - 23).abs() <= 1)
        )
      if outer || edge || mark {
        rgba[index] = if !enabled { b'\x8A' } else { border_r }
        rgba[index + 1] = if !enabled { b'\x8A' } else { border_g }
        rgba[index + 2] = if !enabled { b'\x8A' } else { border_b }
      }
    }
  }
  for y in label_top.max(2)..<(label_top + 32).min(height - 2) {
    for x in 36..<(width - 8) {
      let dest = (y * width + x) * 4
      let source = ((y - label_top) * label_width + x - 36) * 4
      for channel in 0..<4 {
        rgba[dest + channel] = label[source + channel]
      }
    }
  }
  rgba.unsafe_reinterpret_as_bytes()
}

///|
fn control_pixels(
  bounds : @view.Bounds,
  label : Bytes,
  label_top : Int,
  focused : Bool,
) -> Bytes {
  let width = bounds.width
  let height = bounds.height
  let label_width = (width - 16).max(1)
  let rgba = FixedArray::make(width * height * 4, b'\xff')
  let border_r = if focused { b'\xF5' } else { b'\x35' }
  let border_g = if focused { b'\xA1' } else { b'\x50' }
  let border_b = if focused { b'\x5C' } else { b'\x6D' }
  for y in 0..<height {
    for x in 0..<width {
      if x < 2 || x >= width - 2 || y < 2 || y >= height - 2 {
        let offset = (y * width + x) * 4
        rgba[offset] = border_r
        rgba[offset + 1] = border_g
        rgba[offset + 2] = border_b
      }
    }
  }
  for y in label_top.max(2)..<(label_top + 32).min(height - 2) {
    for x in 8..<(width - 8) {
      let dest = (y * width + x) * 4
      let source = ((y - label_top) * label_width + x - 8) * 4
      for channel in 0..<4 {
        rgba[dest + channel] = label[source + channel]
      }
    }
  }
  rgba.unsafe_reinterpret_as_bytes()
}

///|
fn clip_layer(layer : Layer, clip : @view.Bounds?) -> Layer {
  guard clip is Some(clip) else { return layer }
  let bounds = layer.bounds
  let visible = bounds.intersection(clip)
  if visible == Some(bounds) {
    return layer
  }
  guard visible is Some(visible) else {
    return { bounds: { ..clip, width: 0, height: 0, }, pixels: b"", }
  }
  let pixels = Bytes::makei(visible.width * visible.height * 4, index => {
    let x = visible.x - bounds.x + index / 4 % visible.width
    let y = visible.y - bounds.y + index / 4 / visible.width
    layer.pixels[(y * bounds.width + x) * 4 + index % 4]
  })
  { bounds: visible, pixels, }
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
  Ok(layers.filter(layer => layer.bounds.width > 0 && layer.bounds.height > 0))
}
